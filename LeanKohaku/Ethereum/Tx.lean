import LeanKohaku.Ethereum.Address
import LeanKohaku.Crypto.Secp256k1

/-!
# Ethereum transactions

Type-2 (EIP-1559) transactions only to start. We model them at the
abstract level first; byte-level transaction encoding will be reintroduced
when it is needed by a production signing path.
-/

namespace LeanKohaku.Ethereum.Tx

open LeanKohaku.Ethereum.Address
open LeanKohaku.Crypto.Secp256k1

/-- Unsigned EIP-1559 transaction. `value`, `gas*`, `nonce` are Nat — we'll
refine to explicit bit-widths (`UInt256`) after we settle the encoding. -/
structure TxEip1559 where
  chainId              : Nat
  nonce                : Nat
  maxPriorityFeePerGas : Nat
  maxFeePerGas         : Nat
  gasLimit             : Nat
  to                   : Option Address
  value                : Nat
  data                 : ByteArray
  accessList           : List (Address × List ByteArray) := []

/-- Signed transaction bundles the unsigned body with the signature. -/
structure SignedTx where
  unsigned : TxEip1559
  sig      : Signature

end LeanKohaku.Ethereum.Tx
