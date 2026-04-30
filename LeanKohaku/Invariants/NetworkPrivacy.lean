import LeanKohaku.Network.Provider

/-!
# Network privacy invariants
-/

namespace LeanKohaku.Invariants.NetworkPrivacy

open LeanKohaku.Privacy.NetworkPolicy
open LeanKohaku.Network.Provider

theorem strictCli_onlyLocalDaemon (req : NetworkRequest) :
    strictCliPolicy req = true →
      req.peer = Peer.localDaemon ∧
        req.purpose = Purpose.daemonControl ∧
          req.transport = Transport.loopback := by
  cases req with
  | mk peer purpose transport =>
    cases peer <;> cases purpose <;> cases transport <;> simp [strictCliPolicy]

theorem strictDaemon_neverThirdPartyPeer (req : NetworkRequest) :
    strictDaemonPolicy req = true → req.peer ≠ Peer.thirdPartyApi := by
  cases req with
  | mk peer purpose transport =>
    cases peer <;> cases purpose <;> cases transport <;> simp [strictDaemonPolicy]

theorem torDaemon_neverThirdPartyPeer (req : NetworkRequest) :
    torDaemonPolicy req = true → req.peer ≠ Peer.thirdPartyApi := by
  cases req with
  | mk peer purpose transport =>
    cases peer <;> cases purpose <;> cases transport <;> simp [torDaemonPolicy]

theorem strictDaemon_configuredNodeOnlyBroadcast (req : NetworkRequest) :
    strictDaemonPolicy req = true →
      req.peer = Peer.configuredNode →
        req.purpose = Purpose.broadcastTx := by
  cases req with
  | mk peer purpose transport =>
    cases peer <;> cases purpose <;> cases transport <;> simp [strictDaemonPolicy]

theorem strictDaemon_noConfiguredNode (req : NetworkRequest) :
    strictDaemonPolicy req = true → req.peer ≠ Peer.configuredNode := by
  cases req with
  | mk peer purpose transport =>
    cases peer <;> cases purpose <;> cases transport <;> simp [strictDaemonPolicy]

theorem torDaemon_configuredNodeOnlyTor (req : NetworkRequest) :
    torDaemonPolicy req = true →
      req.peer = Peer.configuredNode →
        req.transport = Transport.tor := by
  cases req with
  | mk peer purpose transport =>
    cases peer <;> cases purpose <;> cases transport <;> simp [torDaemonPolicy]

theorem deniedThirdPartyPurposesStrict (req : NetworkRequest) :
    thirdPartyPurpose req.purpose = true →
      strictDaemonPolicy req = false := by
  cases req with
  | mk peer purpose transport =>
    cases peer <;> cases purpose <;> cases transport <;> simp [thirdPartyPurpose, strictDaemonPolicy]

theorem nonBroadcastMethodsAreReads (m : RpcMethod) :
    m ≠ RpcMethod.sendRawTransaction → m.purpose = Purpose.nodeRead := by
  intro h
  cases m <;> simp [RpcMethod.purpose] at *

theorem strictConfiguredProviderOnlyBroadcast (cfg : Config) (op : Operation) :
    permitted strictDaemonPolicy cfg op = true →
      (requestFor cfg op).peer = Peer.configuredNode →
        op.method = RpcMethod.sendRawTransaction := by
  intro h peerEq
  cases cfg with
  | mk backend transport =>
    cases op with
    | mk method params =>
      cases backend <;> cases transport <;> cases method <;>
        simp [permitted, requestFor, peerFor, RpcMethod.purpose, strictDaemonPolicy] at h peerEq ⊢

theorem strictConfiguredProviderDenied (cfg : Config) (op : Operation) :
    permitted strictDaemonPolicy cfg op = true →
      cfg.backend ≠ Backend.configuredNode := by
  intro h
  cases cfg with
  | mk backend transport =>
    cases op with
    | mk method params =>
      cases backend <;> cases transport <;> cases method <;>
        simp [permitted, requestFor, peerFor, RpcMethod.purpose, strictDaemonPolicy] at h ⊢

theorem torConfiguredProviderOnlyTor (cfg : Config) (op : Operation) :
    permitted torDaemonPolicy cfg op = true →
      cfg.backend = Backend.configuredNode →
        cfg.transport = Transport.tor := by
  intro h backendEq
  cases cfg with
  | mk backend transport =>
    cases op with
    | mk method params =>
      cases backend <;> cases transport <;> cases method <;>
        simp [permitted, requestFor, peerFor, RpcMethod.purpose, torDaemonPolicy] at h backendEq ⊢

theorem denyByDefault_denies (req : NetworkRequest) :
    denyByDefault req = false := by
  simp [denyByDefault]

end LeanKohaku.Invariants.NetworkPrivacy
