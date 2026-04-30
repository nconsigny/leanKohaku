import LeanKohaku.Cli.Actions
import LeanKohaku.Network.Provider

/-!
# Local daemon protocol model

This is the daemon-facing counterpart to CLI action preflight. It models
which provider operation the daemon may perform for each wallet action,
without implementing sockets or network transport.
-/

namespace LeanKohaku.Daemon.Protocol

open LeanKohaku.Cli.Actions
open LeanKohaku.Network.Provider
open LeanKohaku.Privacy.NetworkPolicy

structure Request where
  action : Action
  deriving Repr, DecidableEq

inductive Plan where
  | provider (cfg : Config) (op : Operation)
  deriving Repr, DecidableEq

def providerOperation : Action → Operation
  | .balance _ => { method := .getBalance }
  | .send _ _ => { method := .sendRawTransaction }

/-- Strict daemon mode never uses configured-node transport. -/
def strictPlan (req : Request) : Plan :=
  .provider Config.local (providerOperation req.action)

/-- Tor daemon mode can be selected later for configured-node operation. -/
def torPlan (req : Request) : Plan :=
  .provider Config.torConfigured (providerOperation req.action)

def planPermitted (policy : Policy) : Plan → Bool
  | .provider cfg op => permitted policy cfg op

def strictPermitted (req : Request) : Bool :=
  planPermitted strictDaemonPolicy (strictPlan req)

def torPermitted (req : Request) : Bool :=
  planPermitted torDaemonPolicy (torPlan req)

def planSummary : Plan → String
  | .provider cfg op =>
      let req := requestFor cfg op
      s!"backend={cfg.backend.asString} method={op.method.asString} peer={req.peer.asString} purpose={req.purpose.asString} transport={req.transport.asString}"

end LeanKohaku.Daemon.Protocol
