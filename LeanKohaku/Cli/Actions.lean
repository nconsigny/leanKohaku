import LeanKohaku.Cli.Validation
import LeanKohaku.Privacy.NetworkPolicy

/-!
# CLI wallet action preflight

Wallet actions are converted into local daemon requests only after input
validation. This module does not perform socket or network I/O.
-/

namespace LeanKohaku.Cli.Actions

open LeanKohaku.Cli.Validation
open LeanKohaku.Privacy.NetworkPolicy

inductive Action where
  | balance (address : String)
  | send (to : String) (amountWei : Nat)
  deriving Repr, DecidableEq

def Action.valid : Action → Bool
  | .balance address => validAddressString address
  | .send to amountWei => validAddressString to && amountWei > 0

def Action.name : Action → String
  | .balance _ => "balance"
  | .send _ _ => "send"

def daemonRequest (_action : Action) : NetworkRequest :=
  { peer := .localDaemon, purpose := .daemonControl, transport := .loopback }

def preflight (policy : Policy) (action : Action) : Bool :=
  action.valid && policy (daemonRequest action)

def parseBalance (address : String) : Option Action :=
  let action := Action.balance address
  if action.valid then some action else none

def parseSend (to amount : String) : Option Action := do
  let amountWei ← parsePositiveNat amount
  let action := Action.send to amountWei
  if action.valid then some action else none

def actionSummary : Action → String
  | .balance address => s!"balance address={address}"
  | .send to amountWei => s!"send to={to} amountWei={amountWei}"

end LeanKohaku.Cli.Actions
