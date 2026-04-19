/-!
# SHA-256

Needed by BIP32 / BIP39 (HMAC-SHA512 is separate; SHA-256 is used for the
BIP39 checksum and base58check). Implementation deferred.
-/

namespace LeanKohaku.Crypto.Sha256

def sha256 (_input : ByteArray) : ByteArray :=
  ⟨Array.replicate 32 0⟩

end LeanKohaku.Crypto.Sha256
