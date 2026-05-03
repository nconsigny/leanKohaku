import LeanKohaku.Encoding.Json

/-!
# Clearsign-bridge sidecar boundary

The ERC-7730 descriptor walker (calldata + EIP-712 → human intent) is
implemented in `bridge/clearsign/` because viem already speaks the JSON-RPC
shapes we need (function-data decode, ABI parsing) and rewriting it in Lean
adds friction without security upside.

The sidecar is **untrusted** for signing decisions: its output is rendered
to the user as confirmation copy only. The Lean side never decides whether
to broadcast based on `intent` strings; it always re-decodes the signed tx
through the existing RLP / typed-tx / ABI path.

The sidecar performs no network IO, no key access, and no external API
calls — it loads vendored ERC-7730 JSON files at boot and walks them.

This module is the **only** place that spawns the clearsign sidecar.
-/

namespace LeanKohaku.Clearsign.Bridge

open LeanKohaku.Encoding.Json

/-- Default executable name for the clearsign sidecar. -/
def defaultExecutable : String := "leankohaku-clearsign-bridge"

/-- Resolve the bridge executable. The `LEAN_KOHAKU_CLEARSIGN_BRIDGE`
    environment variable overrides for local development. -/
def resolveExecutable : IO String := do
  match (← IO.getEnv "LEAN_KOHAKU_CLEARSIGN_BRIDGE") with
  | some s => pure s
  | none => pure defaultExecutable

structure Request where
  method : String
  params : Json
  id     : Nat
  deriving Repr

inductive Response where
  | ok    (result : Json)
  | err   (code : Int) (message : String) (data : Option Json)
  | crash (stderr : String) (exitCode : UInt32)
  deriving Repr

def encodeRequest (req : Request) : String :=
  compact <| .obj #[
    ("jsonrpc", .str "2.0"),
    ("method",  .str req.method),
    ("params",  req.params),
    ("id",      .num (Int.ofNat req.id))
  ]

private def parseResponse (raw : String) : Response :=
  match parse raw.trimAscii.toString with
  | .error e => Response.crash s!"clearsign returned non-JSON ({e}): {raw}" 0
  | .ok (Json.obj fields) =>
      let lookup (k : String) : Option Json :=
        (fields.find? (fun (key, _) => key == k)).map Prod.snd
      match lookup "error" with
      | some (Json.obj ef) =>
          let code := match (ef.find? (fun (k, _) => k == "code")).map Prod.snd with
            | some (Json.num n) => n
            | _ => -32603
          let msg := match (ef.find? (fun (k, _) => k == "message")).map Prod.snd with
            | some (Json.str s) => s
            | _ => "clearsign error"
          let data := (ef.find? (fun (k, _) => k == "data")).map Prod.snd
          Response.err code msg data
      | _ =>
          match lookup "result" with
          | some j => Response.ok j
          | none => Response.crash s!"clearsign response missing result: {raw}" 0
  | .ok _ => Response.crash s!"clearsign response not a JSON object: {raw}" 0

/-- Spawn the sidecar for one request, write the encoded request as
    `--rpc <json>`, read stdout, decode the response. Same one-shot
    pattern as `LeanKohaku.Privacy.Bridge.callWithEnv`. -/
def call (req : Request) : IO Response := do
  let exe ← resolveExecutable
  let encoded := encodeRequest req
  try
    let child ← IO.Process.spawn {
      cmd := exe,
      args := #["--rpc", encoded],
      stdin := .null,
      stdout := .piped,
      stderr := .inherit
    }
    let stdout ← child.stdout.readToEnd
    let exitCode ← child.wait
    if exitCode == 0 then
      pure (parseResponse stdout)
    else if !stdout.trim.isEmpty then
      pure (parseResponse stdout)
    else
      pure (Response.crash s!"clearsign exited with code {exitCode}" exitCode)
  catch e =>
    pure (Response.crash (toString e) 0)

/-- Render a `Response` as JSON for forwarding to the CLI. Same shape as
    Privacy.Bridge.responseToJson. -/
def responseToJson : Response → Json
  | .ok j => .obj #[("ok", .bool true), ("result", j)]
  | .err code msg data =>
      .obj #[
        ("ok", .bool false),
        ("error", .obj <| #[
          ("code", .num code),
          ("message", .str msg)
        ] ++ (match data with
              | some d => #[("data", d)]
              | none => #[]))
      ]
  | .crash stderr exitCode =>
      .obj #[
        ("ok", .bool false),
        ("crash", .obj #[
          ("stderr", .str stderr),
          ("exitCode", .num (Int.ofNat exitCode.toNat))
        ])
      ]

end LeanKohaku.Clearsign.Bridge
