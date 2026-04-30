import Contracts.R1Account.R1Account

/-!
# R1Account specification
-/

namespace Contracts.R1Account.Spec

open Verity
open Verity.EVM.Uint256
open Contracts.R1Account

def initializedSpec (qx qy : Uint256) (s s' : ContractState) : Prop :=
  s'.storage qxSlot.slot = qx ∧
    s'.storage qySlot.slot = qy ∧
    s'.storage nonceSlot.slot = 0 ∧
    s'.sender = s.sender ∧
    s'.thisAddress = s.thisAddress

def executeAcceptedSpec (s s' : ContractState) : Prop :=
  s'.storage nonceSlot.slot = add (s.storage nonceSlot.slot) 1 ∧
    s'.storage qxSlot.slot = s.storage qxSlot.slot ∧
    s'.storage qySlot.slot = s.storage qySlot.slot ∧
    s'.sender = s.sender ∧
    s'.thisAddress = s.thisAddress

def executeRejectedSpec (s s' : ContractState) : Prop :=
  s'.storage nonceSlot.slot = s.storage nonceSlot.slot ∧
    s'.storage qxSlot.slot = s.storage qxSlot.slot ∧
    s'.storage qySlot.slot = s.storage qySlot.slot

end Contracts.R1Account.Spec
