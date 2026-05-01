import LeanKohaku.Daemon.Server
import LeanKohaku.Privacy.NetworkPolicy
import LeanKohaku.RPC.Outbound

/-!
# Daemon configuration

Small environment-backed resolver for now. File-backed TOML/JSON can layer on
top once the daemon method surface is stable.
-/

namespace LeanKohaku.Daemon.Config

open LeanKohaku.Privacy.NetworkPolicy

def runtimeDir : IO String := do
  match ← IO.getEnv "XDG_RUNTIME_DIR" with
  | some dir => pure dir
  | none => pure "/tmp"

def defaultSocketPath : IO String := do
  pure s!"{← runtimeDir}/leankohaku/leankohaku.sock"

def resolve : IO LeanKohaku.Daemon.Server.Config := do
  let socketPath ←
    match ← IO.getEnv "LEANKOHAKU_SOCKET" with
    | some path => pure path
    | none => defaultSocketPath
  let chainId :=
    match ← IO.getEnv "LEANKOHAKU_CHAIN_ID" with
    | some s =>
        match s.toNat? with
        | some n => n
        | none => 1
    | none => 1
  let policy :=
    match ← IO.getEnv "LEANKOHAKU_NETWORK_POLICY" with
    | some s =>
        match LeanKohaku.Privacy.NetworkPolicy.parsePolicy s with
        | some p => p
        | none => strictDaemonPolicy
    | none => strictDaemonPolicy
  let rpcEndpoint ← LeanKohaku.RPC.Outbound.resolveEndpoint
  pure { socketPath := socketPath, chainId := chainId, policy := policy, rpcEndpoint := rpcEndpoint }

end LeanKohaku.Daemon.Config
