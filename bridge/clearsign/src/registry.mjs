// Load every JSON file from `registry/` at boot and build two indexes:
//   1. (chainId, address) → descriptor — when an ERC-7730 file scopes itself
//      to specific deployments via context.contract.deployments.
//   2. functionSelector → [descriptor, formatKey] — for chain-agnostic
//      descriptors (notably the standard ERC-20 file). Used as a fallback
//      when the (chainId, address) lookup misses.
//
// The walker (decoder.mjs) consults the deployment index first; if no match,
// it tries the selector index. This lets us decode `transfer(...)` against
// any ERC-20 token without enumerating every token in the registry.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { keccak256, toBytes } from "viem";

const SELF_DIR = path.dirname(fileURLToPath(import.meta.url));
const REGISTRY_DIR = path.resolve(SELF_DIR, "..", "registry");

// Strip parameter names from a format key per ERC-7730 §"Function Call":
//   "transfer(address to,uint256 value)" → "transfer(address,uint256)"
// then keccak256 the result, take the leading 4 bytes.
export function formatKeyToSelector(formatKey) {
  // Remove parameter names: anything after a space inside the parens.
  const sig = formatKey.replace(
    /\(([^)]*)\)/,
    (_, inside) =>
      "(" +
      inside
        .split(",")
        .map((p) => p.trim().split(/\s+/)[0])
        .join(",") +
      ")",
  );
  const h = keccak256(toBytes(sig));
  return h.slice(0, 10).toLowerCase(); // "0x" + 8 hex chars
}

export function loadRegistry() {
  const files = fs
    .readdirSync(REGISTRY_DIR)
    .filter((f) => f.endsWith(".json"))
    .map((f) => path.join(REGISTRY_DIR, f));

  // (chainId:address) → descriptor
  const byDeployment = new Map();
  // selector → array of { descriptor, formatKey, formatSpec }
  const bySelector = new Map();

  for (const file of files) {
    let descriptor;
    try {
      descriptor = JSON.parse(fs.readFileSync(file, "utf8"));
    } catch (e) {
      console.error(`[clearsign] skip ${file}: invalid JSON: ${e?.message}`);
      continue;
    }
    descriptor.__source = path.basename(file);

    const deployments = descriptor?.context?.contract?.deployments ?? [];
    for (const d of deployments) {
      if (typeof d?.chainId === "number" && typeof d?.address === "string") {
        const key = `${d.chainId}:${d.address.toLowerCase()}`;
        byDeployment.set(key, descriptor);
      }
    }

    const formats = descriptor?.display?.formats ?? {};
    for (const [formatKey, formatSpec] of Object.entries(formats)) {
      let sel;
      try {
        sel = formatKeyToSelector(formatKey);
      } catch (e) {
        console.error(`[clearsign] skip selector for "${formatKey}": ${e?.message}`);
        continue;
      }
      if (!bySelector.has(sel)) bySelector.set(sel, []);
      bySelector.get(sel).push({ descriptor, formatKey, formatSpec });
    }
  }

  return { byDeployment, bySelector };
}
