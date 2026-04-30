import LeanKohaku.Network.Endpoint

/-!
# Endpoint hygiene invariants
-/

namespace LeanKohaku.Invariants.Endpoint

open LeanKohaku.Network.Endpoint
open LeanKohaku.Privacy.NetworkPolicy

theorem acceptedStrictNoCredentials (ep : Endpoint) :
    acceptedStrict ep = true → ep.credentialed = false := by
  intro h
  cases ep with
  | mk kind scheme transport credentialed =>
    cases kind <;> cases scheme <;> cases transport <;> cases credentialed <;>
      simp [acceptedStrict] at h ⊢

theorem acceptedTorNoCredentials (ep : Endpoint) :
    acceptedTor ep = true → ep.credentialed = false := by
  intro h
  cases ep with
  | mk kind scheme transport credentialed =>
    cases kind <;> cases scheme <;> cases transport <;> cases credentialed <;>
      simp [acceptedTor] at h ⊢

theorem acceptedStrictLocalOnly (ep : Endpoint) :
    acceptedStrict ep = true → ep.kind = EndpointKind.local ∧ ep.transport = Transport.loopback := by
  intro h
  cases ep with
  | mk kind scheme transport credentialed =>
    cases kind <;> cases scheme <;> cases transport <;> cases credentialed <;>
      simp [acceptedStrict] at h ⊢

theorem acceptedTorNeverThirdParty (ep : Endpoint) :
    acceptedTor ep = true → ep.kind ≠ EndpointKind.thirdParty := by
  intro h
  cases ep with
  | mk kind scheme transport credentialed =>
    cases kind <;> cases scheme <;> cases transport <;> cases credentialed <;>
      simp [acceptedTor] at h ⊢

theorem configuredTorAccepted :
    acceptedTor Endpoint.configuredTor = true := by
  rfl

theorem defaultLocalStrictAccepted :
    acceptedStrict Endpoint.defaultLocal = true := by
  rfl

end LeanKohaku.Invariants.Endpoint
