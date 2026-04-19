/-!
# secp256k1

The elliptic curve used by Ethereum signatures. We model it as
`y² = x³ + 7` over `𝔽_p` with the standard base point `G` and prime
order `n`. Point arithmetic and signing will be implemented here.

Once we bring in Mathlib, we can prove group-law correctness against
`Mathlib.AlgebraicGeometry.EllipticCurve`. For now, scaffolding only.
-/

namespace LeanKohaku.Crypto.Secp256k1

/-- Field prime of secp256k1. -/
def p : Nat := 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f

/-- Curve order (prime). -/
def n : Nat := 0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141

/-- Affine point with explicit point-at-infinity. -/
inductive Point where
  | infinity
  | affine (x y : Nat)
  deriving Repr, DecidableEq

/-- Standard generator `G`. -/
def G : Point := .affine
  0x79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798
  0x483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8

/-- ECDSA signature with `v` recovery parameter (EIP-155 adjusted later). -/
structure Signature where
  r : Nat
  s : Nat
  v : UInt8
  deriving Repr, DecidableEq

-- TODO: point add / double / scalar mul, ECDSA sign/verify, recover.

end LeanKohaku.Crypto.Secp256k1
