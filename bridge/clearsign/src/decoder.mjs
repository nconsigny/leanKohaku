// Top-level: input { chainId, to, value, data } → structured intent.
//
// Pipeline:
//   1. Read leading 4-byte selector from `data`.
//   2. Find candidate (descriptor, formatKey) entries via the deployment
//      index keyed by (chainId, to). If none, fall back to the selector
//      index — this covers chain-agnostic descriptors like ERC-20.
//   3. Decode `data` against the format key's ABI item.
//   4. Walk the format spec's `fields` array, resolve paths, run formatters.
//
// Output shape is small + JSON-safe; the Lean side re-validates and renders.
import { decodeCalldata } from "./abi.mjs";
import { formatField } from "./formatters.mjs";
import { formatKeyToSelector } from "./registry.mjs";

export function decodeTxIntent(req, registry) {
  const chainId = Number(req.chainId);
  const to = (req.to ?? "").toLowerCase();
  const value = req.value ?? "0x0";
  const data = req.data ?? "0x";

  if (!data || data.length < 10) {
    return {
      matched: false,
      reason: "calldata too short for a function selector",
      selector: null,
    };
  }
  const selector = data.slice(0, 10).toLowerCase();

  // Candidate set: deployment first (more specific), then selector fallback.
  const candidates = [];
  const depKey = `${chainId}:${to}`;
  const depDescriptor = registry.byDeployment.get(depKey);
  if (depDescriptor) {
    const formats = depDescriptor.display?.formats ?? {};
    for (const [formatKey, formatSpec] of Object.entries(formats)) {
      candidates.push({
        descriptor: depDescriptor,
        formatKey,
        formatSpec,
        source: "deployment",
      });
    }
  }
  for (const entry of registry.bySelector.get(selector) ?? []) {
    candidates.push({ ...entry, source: "selector" });
  }

  // Pick the first candidate whose selector matches the calldata.
  let chosen = null;
  for (const c of candidates) {
    if (formatKeyToSelector(c.formatKey) === selector) {
      chosen = c;
      break;
    }
  }

  if (!chosen) {
    return {
      matched: false,
      reason: depDescriptor
        ? `descriptor for ${depKey} has no format with selector ${selector}`
        : `no descriptor in registry matches (chainId=${chainId}, to=${to}) or selector ${selector}`,
      selector,
    };
  }

  let decoded;
  try {
    decoded = decodeCalldata(chosen.formatKey, data);
  } catch (e) {
    return {
      matched: true,
      partial: true,
      contractName:
        chosen.descriptor?.metadata?.contractName ??
        chosen.descriptor?.context?.$id ??
        null,
      owner: chosen.descriptor?.metadata?.owner ?? null,
      function: chosen.formatKey,
      intent: chosen.formatSpec.intent ?? null,
      selector,
      error: `calldata decode failed: ${e?.message ?? e}`,
    };
  }

  const structured = buildStructuredRoot(chosen.formatKey, decoded.args);

  // Daemon may inject a `tokenMetadata` map: { "0xaddr": {decimals,symbol} }.
  // Addresses are lowercased keys. The tokenAmount formatter consults this
  // before falling back to descriptor.metadata.token / address-tag display.
  const tokenMetadata = (req.tokenMetadata && typeof req.tokenMetadata === "object")
    ? Object.fromEntries(
        Object.entries(req.tokenMetadata).map(([k, v]) => [k.toLowerCase(), v]),
      )
    : {};

  const ctx = {
    descriptor: chosen.descriptor,
    structured,
    container: { chainId, to, value, from: req.from ?? null },
    tokenMetadata,
  };

  const fields = (chosen.formatSpec.fields ?? []).map((f) =>
    formatField(f, ctx),
  );

  return {
    matched: true,
    partial: false,
    contractName:
      chosen.descriptor?.metadata?.contractName ??
      chosen.descriptor?.context?.$id ??
      null,
    owner: chosen.descriptor?.metadata?.owner ?? null,
    source: chosen.descriptor.__source,
    function: chosen.formatKey,
    intent: chosen.formatSpec.intent ?? null,
    selector,
    fields,
  };
}

// Re-parse the format key to extract input names + positions, then expose
// each arg under its declared name (e.g. "to", "value", "params") so
// descriptor paths address them directly.
function buildStructuredRoot(formatKey, args) {
  const m = /\(([^)]*)\)/.exec(formatKey);
  if (!m) return {};
  const params = m[1].split(",").map((p) => p.trim()).filter(Boolean);

  const root = {};
  args.forEach((arg, i) => {
    const decl = params[i] ?? "";
    const parts = decl.split(/\s+/);
    const name = parts.length >= 2 ? parts[parts.length - 1] : `arg${i}`;
    root[name] = arg;
    root[String(i)] = arg;
  });
  return root;
}
