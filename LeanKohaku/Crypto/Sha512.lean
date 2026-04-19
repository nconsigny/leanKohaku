/-!
# SHA-512 and HMAC-SHA512

Used by BIP32 master-key derivation and child-key derivation.
Implementation deferred.
-/

namespace LeanKohaku.Crypto.Sha512

def sha512 (_input : ByteArray) : ByteArray :=
  ⟨Array.replicate 64 0⟩

def hmacSha512 (_key _msg : ByteArray) : ByteArray :=
  ⟨Array.replicate 64 0⟩

end LeanKohaku.Crypto.Sha512
