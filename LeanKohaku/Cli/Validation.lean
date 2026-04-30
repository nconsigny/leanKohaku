import LeanKohaku.Crypto.Hex

/-!
# CLI input validation

These helpers validate user-facing strings before command handlers build
wallet intents. They are deliberately conservative and network-free.
-/

namespace LeanKohaku.Cli.Validation

open LeanKohaku.Crypto

def strip0x : String → String
  | s =>
      match s.toList with
      | '0' :: 'x' :: rest => String.ofList rest
      | '0' :: 'X' :: rest => String.ofList rest
      | _ => s

def allHexChars : List Char → Bool
  | [] => true
  | c :: cs =>
      match Hex.hexDigit? c with
      | some _ => allHexChars cs
      | none => false

def validAddressString (s : String) : Bool :=
  let raw := strip0x s
  raw.toList.length = 40 && allHexChars raw.toList

def validPositiveNatString (s : String) : Bool :=
  match s.toNat? with
  | some n => n > 0
  | none => false

def parsePositiveNat (s : String) : Option Nat :=
  match s.toNat? with
  | some n => if n > 0 then some n else none
  | none => none

theorem parsePositiveNat_some_positive {s : String} {n : Nat} :
    parsePositiveNat s = some n → n > 0 := by
  intro h
  unfold parsePositiveNat at h
  cases hs : s.toNat? with
  | none =>
      simp [hs] at h
  | some parsed =>
      by_cases hp : parsed > 0
      · simp [hs, hp] at h
        subst h
        exact hp
      · simp [hs, hp] at h

end LeanKohaku.Cli.Validation
