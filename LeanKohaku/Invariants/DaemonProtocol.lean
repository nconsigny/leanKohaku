import LeanKohaku.Daemon.Protocol

/-!
# Daemon protocol invariants
-/

namespace LeanKohaku.Invariants.DaemonProtocol

open LeanKohaku.Cli.Actions
open LeanKohaku.Daemon.Protocol
open LeanKohaku.Network.Provider
open LeanKohaku.Privacy.NetworkPolicy

theorem balanceMapsToRead (address : String) :
    (providerOperation (Action.balance address)).method = RpcMethod.getBalance := by
  rfl

theorem sendMapsToBroadcast (to : String) (amountWei : Nat) :
    (providerOperation (Action.send to amountWei)).method = RpcMethod.sendRawTransaction := by
  rfl

theorem strictPlanUsesLocalBackend (req : Request) :
    match strictPlan req with
    | .provider cfg _ => cfg.backend = Backend.localNode ∧ cfg.transport = Transport.loopback := by
  cases req with
  | mk action =>
    cases action <;> simp [strictPlan, Config.local]

theorem strictPlanPermitted (req : Request) :
    strictPermitted req = true := by
  cases req with
  | mk action =>
    cases action <;>
      simp [strictPermitted, strictPlan, planPermitted, providerOperation,
        Config.local, permitted, requestFor, peerFor, RpcMethod.purpose,
        strictDaemonPolicy]

theorem torPlanUsesConfiguredTor (req : Request) :
    match torPlan req with
    | .provider cfg _ => cfg.backend = Backend.configuredNode ∧ cfg.transport = Transport.tor := by
  cases req with
  | mk action =>
    cases action <;> simp [torPlan, Config.torConfigured]

theorem torPlanPermitted (req : Request) :
    torPermitted req = true := by
  cases req with
  | mk action =>
    cases action <;>
      simp [torPermitted, torPlan, planPermitted, providerOperation,
        Config.torConfigured, permitted, requestFor, peerFor,
        RpcMethod.purpose, torDaemonPolicy]

end LeanKohaku.Invariants.DaemonProtocol
