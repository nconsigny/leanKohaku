import LeanKohaku.Privacy.NetworkPolicy

/-!
# JSON-RPC 2.0 client

Minimal client for talking to Ethereum nodes. JSON parsing/serialization
stays in Lean to keep the "everything in Lean" promise.

Transport code must be mediated by `LeanKohaku.Privacy.NetworkPolicy`.
The CLI must never call this module directly. The daemon may use it only
for local/light-client reads and strictly necessary transaction broadcast.
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

/-- Classify an Ethereum JSON-RPC method before transport code can send it. -/
def purposeForMethod (method : String) : Purpose :=
  if method = "eth_sendRawTransaction" then
    Purpose.broadcastTx
  else
    Purpose.nodeRead

def requestPolicyCheck (policy : Policy) (peer : Peer) (transport : Transport) (req : Request) : Bool :=
  policy { peer := peer, purpose := purposeForMethod req.method, transport := transport }

-- TODO: encodeRequest / decodeResponse, `call : Chain → Request → IO Response`.

end LeanKohaku.RPC.JsonRpc
