import LeanKohaku.Privacy.NetworkPolicy

/-!
# Network privacy invariants

These propositions pin down the privacy posture before the daemon and RPC
client grow real network I/O.
-/

namespace LeanKohaku.Invariants.NetworkPrivacy

open LeanKohaku.Privacy.NetworkPolicy

theorem strictCli_onlyLocalDaemon (req : NetworkRequest) :
    strictCliPolicy req = true →
      req.peer = Peer.localDaemon ∧
        req.purpose = Purpose.daemonControl ∧
          req.transport = Transport.loopback := by
  cases req with
  | mk peer purpose transport =>
    cases peer <;> cases purpose <;> cases transport <;> simp [strictCliPolicy]

theorem strictDaemon_neverThirdParty (req : NetworkRequest) :
    strictDaemonPolicy req = true → req.peer ≠ Peer.thirdPartyApi := by
  cases req with
  | mk peer purpose transport =>
    cases peer <;> cases purpose <;> cases transport <;> simp [strictDaemonPolicy]

theorem strictDaemon_configuredNodeOnlyBroadcast (req : NetworkRequest) :
    strictDaemonPolicy req = true →
      req.peer = Peer.configuredNode →
        req.purpose = Purpose.broadcastTx := by
  cases req with
  | mk peer purpose transport =>
    cases peer <;> cases purpose <;> cases transport <;> simp [strictDaemonPolicy]

theorem torDaemon_neverThirdParty (req : NetworkRequest) :
    torDaemonPolicy req = true → req.peer ≠ Peer.thirdPartyApi := by
  cases req with
  | mk peer purpose transport =>
    cases peer <;> cases purpose <;> cases transport <;> simp [torDaemonPolicy]

theorem torDaemon_configuredNodeOnlyTor (req : NetworkRequest) :
    torDaemonPolicy req = true →
      req.peer = Peer.configuredNode →
        req.transport = Transport.tor := by
  cases req with
  | mk peer purpose transport =>
    cases peer <;> cases purpose <;> cases transport <;> simp [torDaemonPolicy]

theorem denyByDefault_denies (req : NetworkRequest) :
    denyByDefault req = false := by
  simp [denyByDefault]

end LeanKohaku.Invariants.NetworkPrivacy
