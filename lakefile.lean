import Lake
open Lake DSL

package "leanKohaku" where
  version := v!"0.1.0"
  -- Mathlib is intentionally omitted for now so `lake build` stays fast
  -- while we iterate on architecture. It will be added when we start
  -- formalizing algebraic proofs (e.g. ZMod / elliptic-curve group laws
  -- for secp256k1).
  leanOptions := #[
    ⟨`pp.unicode.fun, true⟩,
    ⟨`autoImplicit, false⟩
  ]

@[default_target]
lean_lib LeanKohaku where

@[default_target]
lean_exe leankohaku where
  root := `Main
  supportInterpreter := true

@[default_target]
lean_exe «leankohaku-daemon» where
  root := `DaemonMain
  supportInterpreter := true
