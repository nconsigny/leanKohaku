import LeanKohaku.Encoding.Json
import LeanKohaku.Transport.Uds

/-!
# Thin daemon client

Small JSON-RPC client for CLI commands. It transports JSON over the local Unix
socket and does not perform wallet operations locally.
-/

namespace LeanKohaku.Cli.DaemonClient

open LeanKohaku.Encoding.Json

structure RpcError where
  code    : Int
  message : String
  deriving Repr

def runtimeDir : IO String := do
  match ← IO.getEnv "XDG_RUNTIME_DIR" with
  | some dir => pure dir
  | none => pure "/tmp"

def defaultSocketPath : IO String := do
  pure s!"{← runtimeDir}/leankohaku/leankohaku.sock"

def socketPath : IO String := do
  match ← IO.getEnv "LEANKOHAKU_SOCKET" with
  | some path => pure path
  | none => defaultSocketPath

def requestJson (method : String) (params : Json) : Json :=
  .obj #[
    ("jsonrpc", .str "2.0"),
    ("method", .str method),
    ("params", params),
    ("id", .num 1)
  ]

def parseRpcError (json : Json) : RpcError :=
  let code :=
    match getField "code" json with
    | some (.num n) => n
    | _ => -32000
  let message :=
    match getField "message" json >>= asString with
    | some msg => msg
    | none => "daemon error"
  let message :=
    match getField "data" json with
    | some data => message ++ ": " ++ compact data
    | none => message
  { code := code, message := message }

def call (method : String) (params : Json := .arr #[]) : IO (Except RpcError Json) := do
  try
    let conn ← LeanKohaku.Transport.Uds.connect (← socketPath)
    try
      discard <| LeanKohaku.Transport.Uds.write conn (compact (requestJson method params) ++ "\n").toByteArray
      let bytes ← LeanKohaku.Transport.Uds.read conn
      let some text := String.fromUTF8? bytes
        | pure (.error { code := -32700, message := "daemon returned non-UTF8 response" })
      match parse text.trimAscii.toString with
      | .error err => pure (.error { code := -32700, message := err })
      | .ok response =>
          match getField "result" response, getField "error" response with
          | some result, _ => pure (.ok result)
          | _, some err => pure (.error (parseRpcError err))
          | _, _ => pure (.error { code := -32603, message := "malformed daemon response" })
    finally
      LeanKohaku.Transport.Uds.close conn
  catch e =>
    pure (.error { code := -32000, message := e.toString })

def printCall (method : String) (params : Json := .arr #[]) : IO UInt32 := do
  match ← call method params with
  | .ok result =>
      IO.println (pretty result)
      pure 0
  | .error err =>
      IO.eprintln s!"daemon error {err.code}: {err.message}"
      pure 2

def printTextResult (method : String) (params : Json := .arr #[]) : IO UInt32 := do
  match ← call method params with
  | .ok result =>
      match getField "text" result >>= asString with
      | some text => IO.print text
      | none => IO.println (pretty result)
      match getField "exitCode" result >>= asNat with
      | some code => pure (UInt32.ofNat code)
      | none => pure 0
  | .error err =>
      IO.eprintln s!"daemon error {err.code}: {err.message}"
      pure 2

end LeanKohaku.Cli.DaemonClient
