import LeanKohaku.Crypto.Hex
import LeanKohaku.Crypto.Hacl

/-!
# Native secp256k1 boundary

Runtime ECDSA operations are delegated to Bitcoin Core's libsecp256k1 via
small hex-command helpers. `Crypto.Secp256k1` remains the pure specification
surface and is not used for runtime signing.
-/

namespace LeanKohaku.Crypto.Secp256k1Native

def helperSign : String := "leankohaku-secp256k1-sign"
def helperPubkey : String := "leankohaku-secp256k1-pubkey"
def helperRecover : String := "leankohaku-secp256k1-recover"
def helperVerify : String := "leankohaku-secp256k1-verify"

def signIO (privkeyHex digestHex : String) : IO (Except String ByteArray) :=
  Hacl.runHexHelper helperSign #[privkeyHex, digestHex]

def pubkeyIO (privkeyHex : String) (compressed : Bool := true) :
    IO (Except String ByteArray) :=
  let mode := if compressed then "compressed" else "uncompressed"
  Hacl.runHexHelper helperPubkey #[privkeyHex, mode]

def recoverIO (digestHex rHex sHex : String) (v : Nat) :
    IO (Except String ByteArray) :=
  Hacl.runHexHelper helperRecover #[digestHex, rHex, sHex, toString v]

def verifyIO (digestHex rHex sHex pubkeyHex : String) :
    IO (Except String ByteArray) :=
  Hacl.runHexHelper helperVerify #[digestHex, rHex, sHex, pubkeyHex]

end LeanKohaku.Crypto.Secp256k1Native
