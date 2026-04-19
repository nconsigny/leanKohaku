/-!
# BIP39 Mnemonics

Entropy ↔ mnemonic, mnemonic → seed (PBKDF2-HMAC-SHA512, 2048 rounds).
-/

namespace LeanKohaku.Wallet.Mnemonic

structure Mnemonic where
  words : List String
  deriving Repr

-- TODO: entropy → Mnemonic, Mnemonic → seed, wordlist validation + checksum.

end LeanKohaku.Wallet.Mnemonic
