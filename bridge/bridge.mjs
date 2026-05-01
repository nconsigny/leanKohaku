#!/usr/bin/env node
// leankohaku-kohaku-bridge — M1 skeleton.
//
// Untrusted JSON-RPC sidecar invoked by the leanKohaku daemon
// (LeanKohaku/Privacy/Bridge.lean). One-shot mode: receives a single
// JSON-RPC request via `--rpc <json>` and prints a single JSON-RPC
// response on stdout. NDJSON long-lived mode is reserved for M2+.
//
// SECURITY: This process is trusted to perform Railgun / privacy-pools
// circuit work but UNTRUSTED for transaction structure. The Lean side
// must re-decode every prepared tx and only sign through the existing
// TPM-rooted path. Network egress from this process must be bound to
// the daemon's Tor proxy — see HTTPS_PROXY/HTTP_PROXY env wired by the
// daemon spawn site.

const PROTOCOL_VERSION = "0.0.1";

function jsonrpcResult(id, result) {
  return JSON.stringify({ jsonrpc: "2.0", id: id ?? null, result });
}

function jsonrpcError(id, code, message, data) {
  const error = { code, message };
  if (data !== undefined) error.data = data;
  return JSON.stringify({ jsonrpc: "2.0", id: id ?? null, error });
}

function methodNotFound(id, method) {
  return jsonrpcError(id, -32601, `method not found: ${method}`);
}

function dispatch(req) {
  const { method, params, id } = req;
  switch (method) {
    case "ping":
      return jsonrpcResult(id, {
        ok: true,
        bridge: "leankohaku-kohaku-bridge",
        protocol: PROTOCOL_VERSION,
        node: process.versions.node,
      });
    case "version":
      return jsonrpcResult(id, {
        bridge: PROTOCOL_VERSION,
        node: process.versions.node,
      });
    case "listProtocols":
      // M2 will populate these after wiring the @kohaku-eth packages.
      return jsonrpcResult(id, {
        protocols: [
          { name: "railgun", status: "stub" },
          { name: "privacy-pools", status: "stub" },
        ],
      });
    default:
      return methodNotFound(id, method);
  }
}

function parseArgvRpc(argv) {
  const i = argv.indexOf("--rpc");
  if (i < 0 || i + 1 >= argv.length) return null;
  try {
    return JSON.parse(argv[i + 1]);
  } catch (e) {
    return { __parseError: e.message };
  }
}

function main() {
  const argv = process.argv.slice(2);
  const req = parseArgvRpc(argv);
  if (req === null) {
    process.stdout.write(
      jsonrpcError(null, -32700, "expected --rpc <json-rpc-request>") + "\n"
    );
    process.exit(2);
  }
  if (req.__parseError) {
    process.stdout.write(
      jsonrpcError(null, -32700, `parse error: ${req.__parseError}`) + "\n"
    );
    process.exit(2);
  }
  if (!req || typeof req.method !== "string") {
    process.stdout.write(
      jsonrpcError(req?.id ?? null, -32600, "invalid request") + "\n"
    );
    process.exit(2);
  }
  const out = dispatch(req);
  process.stdout.write(out + "\n");
  process.exit(0);
}

main();
