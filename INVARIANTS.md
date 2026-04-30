# Invariants

Living document. Each invariant is (a) stated informally, (b) sketched as a
Lean proposition, (c) tagged with its current proof status, and (d) linked
to the module where the proof lives (or will live).

Status legend:
- 📝 **stated** — proposition written, implementation/proof not started
- 🚧 **in-progress** — proposition formalized, proof partial
- ✅ **proved** — `theorem` closes without `sorry`
- 🔒 **axiomatized** — accepted as axiom pending replacement (e.g. FFI boundary)

---

## Category 1 — Amount arithmetic

### 1.1 Checked subtraction never underflows
A balance debit of `b` from `a` either produces a total `r` with `r + b = a`,
or explicitly fails with `none`. `Nat.sub` silent-clamps to zero, which would
be a catastrophic bug for wallet accounting.

**Prop:** `∀ a b r, subChecked a b = some r → r + b = a`
**Status:** ✅ proved — `LeanKohaku/Invariants/Amount.lean::subChecked_preserves_total`

### 1.2 Sum of outputs ≤ available balance
For any multi-output send, the wallet refuses to sign unless the sum of
outgoing amounts plus fees is ≤ the sending account's balance. The abstract
model is in `LeanKohaku/Invariants/Wallet.lean`: `State`, `Send`, `apply`.

**Props:**
- `apply_some_affordable` — `apply σ s = some σ' → s.affordable σ`
- `apply_sender_debited` — `apply σ s = some σ' → σ'.balance s.sender + s.total = σ.balance s.sender`
- `apply_non_sender_balance` — non-sender accounts grow by exactly the sum of outputs addressed to them.

**Status:** ✅ proved — `LeanKohaku/Invariants/Wallet.lean`

---

## Category 2 — Transaction well-formedness

### 2.1 EIP-1559 fee relation
`maxPriorityFeePerGas ≤ maxFeePerGas` — otherwise the tx is invalid per
EIP-1559 and will be rejected by every mainnet node.

**Prop:** part of `wellFormed`
**Status:** ✅ defined (no theorem needed — it's the definition)
**Location:** `LeanKohaku/Invariants/TxWellFormed.lean`

### 2.2 Intrinsic gas lower bound
`gasLimit ≥ 21_000` for any plain value transfer; higher lower bounds apply
when `data` is non-empty (4 gas per zero byte, 16 per non-zero).

**Prop:** `wellFormed` currently encodes only the bare-transfer bound;
extend to calldata-aware bound next.
**Status:** 🚧 partial

### 2.3 Chain-ID match
The signed chain-id must match the configured chain, to prevent cross-chain
replay.

**Prop:** part of `wellFormed`
**Status:** ✅ defined

---

## Category 3 — Signing

### 3.1 Signed-amount integrity
The `value` field the user confirmed is bit-identical to the `value` in the
broadcast tx. No LLM-driven rewrite, no silent rounding.

**Prop:** `∀ userIntent tx, broadcast tx → confirmed userIntent →
          userIntent.value = tx.value`
**Status:** 📝 stated — requires threading a `UserIntent` type through the CLI

### 3.2 Deterministic nonce use
Once a nonce `k` has been signed for account `a`, the wallet never signs
another tx with nonce `≤ k` for `a`.

**Prop:** `∀ l a n, validNext l a n → n > (l a).getD 0`
**Status:** 📝 stated — `LeanKohaku/Invariants/Nonce.lean`

### 3.3 Signature recoverability
For every signed tx produced by the wallet, `ecrecover(hash, sig) = pubkey`
of the signing account. (Requires secp256k1 spec first.)

**Prop:** TBD (depends on `Crypto.Secp256k1` implementation)
**Status:** 📝 stated

---

## Category 4 — Encoding

### 4.1 RLP roundtrip
Every RLP item decodes back to itself after encoding.

**Prop:** `∀ i : Rlp.Item, Rlp.decode (Rlp.encode i) = some (i, ByteArray.empty)`
**Status:** 📝 stated — `LeanKohaku/Encoding/Rlp.lean`

### 4.2 Hex roundtrip
`decode ∘ encode = some` on byte arrays.

**Prop:** `∀ b : ByteArray, Hex.decode (Hex.encode b) = some b`
**Status:** 📝 stated — `LeanKohaku/Crypto/Hex.lean`

---

## Category 5 — Railgun / privacy notes (later)

### 5.1 No double-spend
A Railgun note's nullifier, once observed in a proven spend, cannot appear
in another valid spend.

**Prop:** TBD — requires modeling the Railgun note tree and nullifier set.
**Status:** 📝 stated (future)

### 5.2 Shield conservation
Sum of values shielded in = sum of notes created + fee.

**Prop:** TBD
**Status:** 📝 stated (future)

### 5.9 CLI wallet actions preflight only through local daemon
`balance` and `send` are validated locally, then classified as local daemon
control over loopback. They do not directly contact nodes or third-party
services.

**Props:**
- `daemonRequest action = { peer := localDaemon, purpose := daemonControl, transport := loopback }`
- `preflight policy action = true → action.valid = true`
- `preflight strictCliPolicy action = true → strictCliPolicy (daemonRequest action) = true`
- `parseSend to amount = some action → ∃ n, action = send to n ∧ n > 0`

**Status:** ✅ proved — `LeanKohaku/Invariants/CliActions.lean`

### 5.10 Daemon action plans stay inside modeled provider operations
The daemon maps `balance` to `eth_getBalance` and `send` to
`eth_sendRawTransaction`. Strict plans use the local node over loopback;
Tor plans use configured-node Tor transport.

**Props:**
- `providerOperation (balance address) = eth_getBalance`
- `providerOperation (send to amountWei) = eth_sendRawTransaction`
- `strictPermitted req = true`
- `torPermitted req = true`

**Status:** ✅ proved — `LeanKohaku/Invariants/DaemonProtocol.lean`

### 5.11 Endpoint hygiene rejects credentialed and third-party endpoints
Endpoint policy is separate from request policy so hosted APIs and hidden
API-key dependencies can be rejected before transport code exists.

**Props:**
- `acceptedStrict ep = true → ep.credentialed = false`
- `acceptedTor ep = true → ep.credentialed = false`
- `acceptedStrict ep = true → ep.kind = local ∧ ep.transport = loopback`
- `acceptedTor ep = true → ep.kind ≠ thirdParty`

**Status:** ✅ proved — `LeanKohaku/Invariants/Endpoint.lean`

---

## Category 6 — Network privacy

### 6.1 CLI only talks to the local daemon
The CLI must not contact Ethereum nodes or external services directly. It
may only use local daemon control over loopback.

**Prop:** `strictCliPolicy req = true → req.peer = localDaemon ∧ req.purpose = daemonControl ∧ req.transport = loopback`
**Status:** ✅ proved — `LeanKohaku/Invariants/NetworkPrivacy.lean::strictCli_onlyLocalDaemon`

### 6.2 Daemon policies never allow third-party API peers
The daemon is the only component allowed to perform node I/O, but strict
and Tor policies reject third-party API peers.

**Props:**
- `strictDaemonPolicy req = true → req.peer ≠ thirdPartyApi`
- `torDaemonPolicy req = true → req.peer ≠ thirdPartyApi`

**Status:** ✅ proved — `LeanKohaku/Invariants/NetworkPrivacy.lean`

### 6.3 Strict mode denies configured-node access
Under strict policy, configured-node access is denied entirely. Remote
configured-node access requires the explicit Tor policy.

**Props:**
- `strictDaemonPolicy req = true → req.peer ≠ configuredNode`
- `permitted strictDaemonPolicy cfg op = true → cfg.backend ≠ configuredNode`

**Status:** ✅ proved — `LeanKohaku/Invariants/NetworkPrivacy.lean`

### 6.4 Third-party purposes are denied
Analytics, price quotes, metadata/indexer lookup, fiat/onramp calls, crash
reports, and discovery are not wallet-network purposes.

**Prop:** `thirdPartyPurpose req.purpose = true → strictDaemonPolicy req = false`
**Status:** ✅ proved — `LeanKohaku/Invariants/NetworkPrivacy.lean::deniedThirdPartyPurposesStrict`

### 6.5 Tor configured-node access is Tor-only
When configured-node access is enabled via Tor policy, it must use Tor
transport.

**Props:**
- `torDaemonPolicy req = true → req.peer = configuredNode → req.transport = tor`
- `permitted torDaemonPolicy cfg op = true → cfg.backend = configuredNode → cfg.transport = tor`

**Status:** ✅ proved — `LeanKohaku/Invariants/NetworkPrivacy.lean`

---

## How we extend this file

1. New invariant idea arises during implementation or review.
2. Add it here with a stub Lean proposition (no proof yet).
3. Open a module under `LeanKohaku/Invariants/` if one doesn't exist.
4. Write the proposition formally; mark 🚧 once `theorem … := by sorry` compiles.
5. Replace `sorry` with a real proof; flip to ✅.
