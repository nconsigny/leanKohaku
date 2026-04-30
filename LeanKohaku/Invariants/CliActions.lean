import LeanKohaku.Cli.Actions

/-!
# CLI action invariants
-/

namespace LeanKohaku.Invariants.CliActions

open LeanKohaku.Cli.Actions
open LeanKohaku.Privacy.NetworkPolicy

theorem daemonRequestAlwaysLocal (action : Action) :
    (daemonRequest action).peer = Peer.localDaemon ∧
      (daemonRequest action).purpose = Purpose.daemonControl ∧
        (daemonRequest action).transport = Transport.loopback := by
  cases action <;> simp [daemonRequest]

theorem preflightImpliesValid (policy : Policy) (action : Action) :
    preflight policy action = true → action.valid = true := by
  intro h
  cases action <;> simp [preflight] at h ⊢
  · exact h.left
  · exact h.left

theorem preflightStrictCliImpliesLocalDaemon (action : Action) :
    preflight strictCliPolicy action = true →
      strictCliPolicy (daemonRequest action) = true := by
  intro h
  cases action <;> simp [preflight] at h ⊢
  · exact h.right
  · exact h.right

theorem parsedSendPositive (to amount : String) (action : Action) :
    parseSend to amount = some action →
      ∃ n, action = Action.send to n ∧ n > 0 := by
  intro h
  unfold parseSend at h
  cases hn : LeanKohaku.Cli.Validation.parsePositiveNat amount with
  | none =>
      simp [hn] at h
  | some n =>
      by_cases hv : (Action.send to n).valid
      · simp [hn, hv] at h
        subst h
        exists n
        exact ⟨rfl, LeanKohaku.Cli.Validation.parsePositiveNat_some_positive hn⟩
      · simp [hn, hv] at h

end LeanKohaku.Invariants.CliActions
