import LeanKohaku.LightClient.Provider

/-!
# Light-client invariants

These proofs connect the Kohaku-style provider abstraction to the strict
network policy.
-/

namespace LeanKohaku.Invariants.LightClient

open LeanKohaku.LightClient.Provider
open LeanKohaku.Privacy.NetworkPolicy

theorem nonBroadcastMethodsAreReads (m : RpcMethod) :
    m ≠ RpcMethod.sendRawTransaction → m.purpose = Purpose.nodeRead := by
  intro h
  cases m <;> simp [RpcMethod.purpose] at *

theorem strictPolicyPermittedNeverThirdParty (cfg : Config) (op : Operation) :
    permitted strictDaemonPolicy cfg op = true →
      (requestFor cfg op).peer ≠ Peer.thirdPartyApi := by
  intro h
  cases cfg with
  | mk backend chainId transport allowLogBypass =>
    cases op with
    | mk method params =>
      cases backend <;> cases transport <;> cases method <;>
        simp [permitted, requestFor, peerFor, RpcMethod.purpose, strictDaemonPolicy] at h ⊢

theorem configuredPeerOnlyBroadcast (cfg : Config) (op : Operation) :
    permitted strictDaemonPolicy cfg op = true →
      (requestFor cfg op).peer = Peer.configuredNode →
        op.method = RpcMethod.sendRawTransaction := by
  intro h peerEq
  cases cfg with
  | mk backend chainId transport allowLogBypass =>
    cases op with
    | mk method params =>
      cases backend <;> cases transport <;> cases method <;>
        simp [permitted, requestFor, peerFor, RpcMethod.purpose, strictDaemonPolicy] at h peerEq ⊢

theorem torPolicyConfiguredPeerOnlyTor (cfg : Config) (op : Operation) :
    permitted torDaemonPolicy cfg op = true →
      (requestFor cfg op).peer = Peer.configuredNode →
        (requestFor cfg op).transport = Transport.tor := by
  intro h peerEq
  cases cfg with
  | mk backend chainId transport allowLogBypass =>
    cases op with
    | mk method params =>
      cases backend <;> cases transport <;> cases method <;>
        simp [permitted, requestFor, peerFor, RpcMethod.purpose, torDaemonPolicy] at h peerEq ⊢

theorem defaultMainnetLogBypassDisabled :
    permittedLogBypass strictDaemonPolicy Config.defaultMainnet = false := by
  simp [permittedLogBypass, Config.defaultMainnet]

end LeanKohaku.Invariants.LightClient
