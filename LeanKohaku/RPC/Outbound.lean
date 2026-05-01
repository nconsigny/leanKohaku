import LeanKohaku.Encoding.Json
import LeanKohaku.Network.Provider
import LeanKohaku.Privacy.NetworkPolicy
import LeanKohaku.RPC.JsonRpc

/-!
# Daemon outbound Ethereum JSON-RPC

Production transport boundary for daemon-to-node calls. Every request is
classified before `curl` is invoked.
-/

namespace LeanKohaku.RPC.Outbound

open LeanKohaku.Encoding.Json
open LeanKohaku.Network.Provider
open LeanKohaku.Privacy.NetworkPolicy

structure Endpoint where
  url       : String
  backend   : Backend
  transport : Transport
  deriving Repr

def isLoopbackUrl (url : String) : Bool :=
  url.startsWith "http://127.0.0.1" ||
  url.startsWith "http://localhost" ||
  url.startsWith "http://[::1]" ||
  url.startsWith "http://0.0.0.0"

def endpointFromUrl (url : String) (transport? : Option Transport := none) : Endpoint :=
  if isLoopbackUrl url then
    { url := url, backend := .localNode, transport := .loopback }
  else
    { url := url, backend := .configuredNode, transport := transport?.getD .direct }

def resolveEndpoint : IO Endpoint := do
  let url ←
    match ← IO.getEnv "LEANKOHAKU_RPC_URL" with
    | some url => pure url
    | none => pure "http://127.0.0.1:8545"
  let transport? ←
    match ← IO.getEnv "LEANKOHAKU_RPC_TRANSPORT" with
    | some "tor" => pure (some Transport.tor)
    | some "direct" => pure (some Transport.direct)
    | some "loopback" => pure (some Transport.loopback)
    | _ => pure none
  pure (endpointFromUrl url transport?)

def providerConfig (endpoint : Endpoint) : LeanKohaku.Network.Provider.Config :=
  { backend := endpoint.backend, transport := endpoint.transport }

def requestAllowed (policy : Policy) (endpoint : Endpoint)
    (method : RpcMethod) : Bool :=
  permitted policy (providerConfig endpoint) { method := method }

def call (policy : Policy) (endpoint : Endpoint) (method : RpcMethod)
    (params : Json) : IO (Except String Json) := do
  unless requestAllowed policy endpoint method do
    return .error s!"network policy denied method={method.asString} backend={endpoint.backend.asString} transport={endpoint.transport.asString}"
  try
    let raw ← LeanKohaku.RPC.JsonRpc.callRaw endpoint.url
      { method := method.asString, params := params, id := 1 }
    match parse raw.trimAscii.toString with
    | .error err => pure (.error s!"invalid JSON-RPC response: {err}")
    | .ok json =>
        match getField "result" json, getField "error" json with
        | some result, _ => pure (.ok result)
        | _, some err => pure (.error s!"Ethereum JSON-RPC error: {compact err}")
        | _, _ => pure (.error "malformed Ethereum JSON-RPC response")
  catch e =>
    pure (.error e.toString)

def getBalance (policy : Policy) (endpoint : Endpoint)
    (address : String) (block : String := "latest") : IO (Except String Json) :=
  call policy endpoint .getBalance (.arr #[.str address, .str block])

def getTransactionCount (policy : Policy) (endpoint : Endpoint)
    (address : String) (block : String := "latest") : IO (Except String Json) :=
  call policy endpoint .getTransactionCount (.arr #[.str address, .str block])

def gasPrice (policy : Policy) (endpoint : Endpoint) : IO (Except String Json) :=
  call policy endpoint .gasPrice (.arr #[])

def maxPriorityFeePerGas (policy : Policy) (endpoint : Endpoint) : IO (Except String Json) :=
  call policy endpoint .maxPriorityFeePerGas (.arr #[])

def estimateGas (policy : Policy) (endpoint : Endpoint) (tx : Json)
    (block : String := "latest") : IO (Except String Json) :=
  call policy endpoint .estimateGas (.arr #[tx, .str block])

def ethCall (policy : Policy) (endpoint : Endpoint)
    (to data : String) (block : String := "latest") : IO (Except String Json) :=
  call policy endpoint .call
    (.arr #[
      .obj #[("to", .str to), ("data", .str data)],
      .str block
    ])

def sendRawTransaction (policy : Policy) (endpoint : Endpoint)
    (rawTx : String) : IO (Except String Json) :=
  call policy endpoint .sendRawTransaction (.arr #[.str rawTx])

end LeanKohaku.RPC.Outbound
