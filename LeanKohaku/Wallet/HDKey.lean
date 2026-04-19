/-!
# BIP32 HD Key derivation

Master key from seed, hardened / non-hardened child derivation,
path parsing (`m/44'/60'/0'/0/0`).
-/

namespace LeanKohaku.Wallet.HDKey

structure ExtendedKey where
  key       : ByteArray
  chainCode : ByteArray
  depth     : UInt8
  index     : UInt32

-- TODO: fromSeed, deriveChild, derivePath.

end LeanKohaku.Wallet.HDKey
