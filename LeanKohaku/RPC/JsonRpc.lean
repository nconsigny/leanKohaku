import LeanKohaku.Privacy.NetworkPolicy

/-!
# JSON-RPC 2.0 client

Minimal client for talking to Ethereum nodes. JSON parsing/serialization
stays in Lean to keep the "everything in Lean" promise.

Network I/O must be mediated by `LeanKohaku.Privacy.NetworkPolicy`.
The CLI must never call this module directly; the daemon may only use it
for local-node reads and strictly necessary transaction broadcasts.
-/

namespace LeanKohaku.RPC.JsonRpc

open LeanKohaku.Privacy.NetworkPolicy

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

/-- Classify an Ethereum JSON-RPC call before any transport code can send it. -/
def purposeForMethod (method : String) : Purpose :=
  if method = "eth_sendRawTransaction" then
    Purpose.broadcastTx
  else
    Purpose.nodeRead

def requestPolicyCheck (policy : Policy) (peer : Peer) (transport : Transport) (req : Request) : Bool :=
  policy { peer := peer, purpose := purposeForMethod req.method, transport := transport }

-- TODO: encodeRequest / decodeResponse, `call : Chain → Request → IO Response`.

end LeanKohaku.RPC.JsonRpc
