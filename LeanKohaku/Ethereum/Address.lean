/-!
# Ethereum addresses

20-byte addresses with EIP-55 mixed-case checksum encoding.
-/

namespace LeanKohaku.Ethereum.Address

/-- A 20-byte Ethereum address wrapped in a dependent pair with a length proof. -/
structure Address where
  bytes : ByteArray
  sizeOk : bytes.size = 20

-- TODO: fromHex : String → Option Address
-- TODO: toChecksum : Address → String  (EIP-55)

end LeanKohaku.Ethereum.Address
