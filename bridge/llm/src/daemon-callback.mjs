// Sidecar → daemon callback. The LLM sidecar connects back to the daemon's
// UDS socket to read chain state under the daemon's policy gate. This keeps
// the model from hallucinating balances or gas prices and ensures every
// outbound RPC is policy-checked the same way the rest of the daemon's
// chain reads are.
//
// Reentrancy: the daemon spawned this sidecar one-shot; we connect back to
// the same socket while the original spawn's response pipe is still open.
// The daemon's UDS handler accepts new connections concurrently, so the
// callback gets served on a fresh connection — no deadlock.
//
// Trust: the model is still untrusted. These tools read only — they cannot
// sign, cannot send raw txs, cannot set state. The daemon enforces the
// boundary; the sidecar just speaks JSON-RPC.
import net from "node:net";
import path from "node:path";
import os from "node:os";

function socketPath() {
  if (process.env.LEANKOHAKU_SOCKET) return process.env.LEANKOHAKU_SOCKET;
  const runtimeDir = process.env.XDG_RUNTIME_DIR || "/tmp";
  return path.join(runtimeDir, "leankohaku", "leankohaku.sock");
}

let _id = 1;

/** One-shot JSON-RPC over UDS. Returns `{ ok, result }` on success or
 *  `{ ok: false, error }` on any failure (transport, RPC error, timeout).
 *  Caller-side timeout is 10s — the daemon's chain RPCs can take a few
 *  hundred ms, so this is generous but bounded. */
export function daemonCall(method, params, timeoutMs = 10_000) {
  return new Promise((resolve) => {
    const sock = net.createConnection(socketPath());
    let buffer = "";
    let settled = false;

    const settle = (r) => {
      if (settled) return;
      settled = true;
      try {
        sock.end();
      } catch {}
      resolve(r);
    };

    const timer = setTimeout(() => {
      settle({ ok: false, error: { code: -32603, message: `daemon callback timeout after ${timeoutMs}ms` } });
    }, timeoutMs);

    sock.on("connect", () => {
      const req = { jsonrpc: "2.0", method, params: params ?? {}, id: _id++ };
      sock.write(JSON.stringify(req) + "\n");
    });

    sock.on("data", (chunk) => {
      buffer += chunk.toString("utf8");
      let nl;
      while ((nl = buffer.indexOf("\n")) !== -1) {
        const frame = buffer.slice(0, nl).trim();
        buffer = buffer.slice(nl + 1);
        if (!frame) continue;
        let parsed;
        try {
          parsed = JSON.parse(frame);
        } catch (e) {
          settle({ ok: false, error: { code: -32700, message: `daemon emitted invalid JSON: ${frame}` } });
          return;
        }
        const hasResult = Object.prototype.hasOwnProperty.call(parsed, "result");
        const hasError = Object.prototype.hasOwnProperty.call(parsed, "error");
        if (!hasResult && !hasError) continue; // notifications — ignore
        clearTimeout(timer);
        if (hasError) {
          settle({ ok: false, error: parsed.error });
        } else {
          settle({ ok: true, result: parsed.result });
        }
        return;
      }
    });

    sock.on("error", (e) => {
      clearTimeout(timer);
      settle({ ok: false, error: { code: -32603, message: `daemon transport error: ${e.message}` } });
    });

    sock.on("close", () => {
      clearTimeout(timer);
      if (!settled) {
        settle({ ok: false, error: { code: -32603, message: "daemon closed connection before responding" } });
      }
    });
  });
}
