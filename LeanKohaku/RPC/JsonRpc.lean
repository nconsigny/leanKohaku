/-!
# JSON-RPC 2.0 client

Minimal client for talking to Ethereum nodes. We'll implement JSON
parsing/serialization in-Lean to keep the "everything in Lean" promise;
network I/O will be via `IO.Process` piped to `curl` initially, then
a native HTTP client once we have one.
-/

namespace LeanKohaku.RPC.JsonRpc

structure Request where
  method : String
  params : List String  -- placeholder; will become a proper Json value
  id     : Nat
  deriving Repr

structure Response where
  id     : Nat
  result : Option String
  error  : Option String
  deriving Repr

-- TODO: encodeRequest / decodeResponse, `call : Chain → Request → IO Response`.

end LeanKohaku.RPC.JsonRpc
