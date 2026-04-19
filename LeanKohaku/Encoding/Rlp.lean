/-!
# Recursive Length Prefix (RLP)

Ethereum's canonical serialization for transactions, receipts, and trie
nodes. Spec: https://ethereum.org/en/developers/docs/data-structures-and-encoding/rlp/

Key property we want to prove: `decode ∘ encode = id` on the abstract
`Item` type (canonical roundtrip).
-/

namespace LeanKohaku.Encoding.Rlp

/-- Abstract RLP item: either a byte string or a list of items. -/
inductive Item where
  | str (bytes : ByteArray)
  | list (items : List Item)
  deriving Inhabited

-- TODO: encode : Item → ByteArray
-- TODO: decode : ByteArray → Option (Item × ByteArray)
-- TODO: theorem decode_encode : ∀ i, decode (encode i) = some (i, ByteArray.empty)

end LeanKohaku.Encoding.Rlp
