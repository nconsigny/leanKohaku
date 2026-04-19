/-!
# Keccak-256

Keccak-256 (the pre-NIST variant used by Ethereum, **not** SHA3-256).
Implementation deferred — we'll port a well-audited reference once the
surrounding API is stable.

The spec we'll follow: FIPS-202 Keccak-f[1600] with rate = 1088, capacity = 512,
padding = `0x01 … 0x80` (multi-rate, domain separator `0x01`).
-/

namespace LeanKohaku.Crypto.Keccak

/-- Keccak-256 digest of a byte array. **Unimplemented.** -/
def keccak256 (_input : ByteArray) : ByteArray :=
  -- TODO: implement Keccak-f[1600] permutation + sponge
  ⟨Array.replicate 32 0⟩

end LeanKohaku.Crypto.Keccak
