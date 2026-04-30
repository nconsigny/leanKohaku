# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`leanKohaku` is a formally-verified Ethereum wallet daemon written entirely in **Lean 4** (pinned to `leanprover/lean4:v4.29.1` via `lean-toolchain`). It is a ground-up re-architecture of the TypeScript [`kohaku-ai`](https://github.com/jiayaoqijia/kohaku-ai) project; no runtime code is shared. The CLI-first surface talks to a long-running daemon over a Unix domain socket. Everything (secp256k1, Keccak, RLP, BIP32/39, JSON-RPC) is implemented in Lean — no FFI to external crypto — so the signing path can be reasoned about in the same type system.

## Build & run

```bash
elan toolchain install $(cat lean-toolchain)   # first-time setup
lake build                                      # builds lib + both executables
```

Artifacts land in `.lake/build/bin/`:
- `leankohaku`         — CLI (root: `Main.lean`)
- `leankohaku-daemon`  — daemon (root: `DaemonMain.lean`)

Build a single module while iterating on proofs: `lake build LeanKohaku.Invariants.Wallet`.

CI: `.github/workflows/lean_action_ci.yml` runs `leanprover/lean-action@v1` on push / PR — same as `lake build` locally. There is no separate test runner yet; proofs ARE the tests, and `lake build` fails if any `theorem` has a `sorry` or fails to typecheck.

Mathlib is intentionally **not** a dependency (see `lakefile.lean`) to keep build times short while the architecture is in flux. Add it only when starting ZMod / elliptic-curve algebraic proofs.

Lake options set repo-wide: `autoImplicit := false` (every type variable must be bound explicitly) and `pp.unicode.fun := true`.

## Architecture

Three-layer structure; dependency flows downward and the `Invariants` tree is where proved properties live alongside the abstract models they constrain.

1. **Primitives** — `LeanKohaku/Crypto/` (Hex, Keccak, Sha256/512, Secp256k1), `LeanKohaku/Encoding/Rlp.lean`. Pure, no IO.
2. **Domain** — `LeanKohaku/Ethereum/` (Address, Chain, Tx), `LeanKohaku/Wallet/` (BIP39 Mnemonic, BIP32 HDKey). Builds on primitives.
3. **Surfaces** — `LeanKohaku/RPC/JsonRpc.lean`, `LeanKohaku/Daemon/Server.lean`, `LeanKohaku/Cli/Commands.lean`. The CLI parses argv to a `Command` ADT; `daemon` delegates to `Daemon.Server.run`. The daemon is currently a stub — `run` just prints a not-implemented line.

`LeanKohaku.lean` is import-only and re-exports every module, so downstream code writes `import LeanKohaku`.

## Invariants workflow

`INVARIANTS.md` is the living source of truth for properties the wallet must satisfy. Every invariant is tagged 📝 stated → 🚧 in-progress → ✅ proved (or 🔒 axiomatized for FFI boundaries). The workflow when adding a new property:

1. Add an informal statement and stub `theorem` in `INVARIANTS.md`.
2. Formalize it under `LeanKohaku/Invariants/<Topic>.lean` (create the module if absent).
3. Once `theorem … := by sorry` typechecks, flip to 🚧 and update the status table in `README.md`.
4. Replace `sorry` with a real proof; flip to ✅ and cite the theorem name + module in `INVARIANTS.md`.

Currently proved: **1.1** (`subChecked_preserves_total` in `Invariants/Amount.lean`) and **1.2** (three theorems in `Invariants/Wallet.lean` — `apply_some_affordable`, `apply_sender_debited`, `apply_non_sender_balance`). **2.1** and **2.3** are `wellFormed`-by-definition in `Invariants/TxWellFormed.lean`.

The `Invariants/Wallet.lean` abstract wallet (`State`, `Output`, `Send`, `apply`) is deliberately thin — `AccountId` is a `String`, balances are `Nat`, there is no crypto. Operational wallet types in `LeanKohaku/Wallet/` and `LeanKohaku/Ethereum/` will eventually refine these. Keep that separation: the abstract model exists to make proofs tractable, not to be the runtime.

Use `Option`-returning checked arithmetic (`Amount.subChecked`) rather than raw `Nat.sub` for any balance computation — silent clamping to zero would be a catastrophic accounting bug and invariant 1.1 exists precisely to rule it out.
