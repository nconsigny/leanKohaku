import Contracts.R1Account.R1Account

/-!
# R1Account invariants
-/

namespace Contracts.R1Account.Invariants

open Verity
open Contracts.R1Account

def publicKeyUnchanged (s s' : ContractState) : Prop :=
  s'.storage qxSlot.slot = s.storage qxSlot.slot ∧
    s'.storage qySlot.slot = s.storage qySlot.slot

def nonceAdvancedByOne (s s' : ContractState) : Prop :=
  s'.storage nonceSlot.slot = Verity.EVM.Uint256.add (s.storage nonceSlot.slot) 1

end Contracts.R1Account.Invariants
