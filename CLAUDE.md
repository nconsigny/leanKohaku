# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`leanKohaku` is a formally-verified Ethereum wallet daemon written entirely in **Lean 4** (pinned to `leanprover/lean4:v4.29.1` via `lean-toolchain`). It is a ground-up re-architecture of the TypeScript [`kohaku-ai`](https://github.com/jiayaoqijia/kohaku-ai) project; no runtime code is shared. The CLI-first surface talks to a long-running daemon over a Unix domain socket. The current critical path models network policy, local TPM custody, P-256/R1 account verification, and Sepolia dev execution in Lean, while avoiding FFI crypto in wallet logic.

## Build & run

```bash
elan toolchain install $(cat lean-toolchain)   # first-time setup
lake build                                      # builds lib + both executables
```

Artifacts land in `.lake/build/bin/`:
- `leankohaku`         — CLI (root: `LeanKohaku/App/Main.lean`)
- `leankohaku-daemon`  — daemon (root: `LeanKohaku/App/DaemonMain.lean`)

Build a single module while iterating on proofs: `lake build LeanKohaku.Invariants.Wallet`.

CI: `.github/workflows/lean_action_ci.yml` runs `leanprover/lean-action@v1` on push / PR — same as `lake build` locally. There is no separate test runner yet; proofs ARE the tests, and `lake build` fails if any `theorem` has a `sorry` or fails to typecheck.

Mathlib is intentionally **not** a dependency (see `lakefile.lean`) to keep build times short while the architecture is in flux. Add it only when starting ZMod / elliptic-curve algebraic proofs.

Lake options set repo-wide: `autoImplicit := false` (every type variable must be bound explicitly) and `pp.unicode.fun := true`.

## Architecture

Three-layer structure; dependency flows downward and the `Invariants` tree is where proved properties live alongside the abstract models they constrain.

1. **Primitives** — `LeanKohaku/Crypto/` (Hex, Secp256k1 scaffolding). Pure, no IO.
2. **Domain** — `LeanKohaku/Ethereum/`, `LeanKohaku/Wallet/`, `LeanKohaku/Keystore/`, `LeanKohaku/Contract/`. Runtime TPM2 integration is isolated in `Keystore/Tpm2Runtime.lean`.
3. **Surfaces** — `LeanKohaku/RPC/`, `LeanKohaku/Daemon/`, `LeanKohaku/Cli/`, and executable roots under `LeanKohaku/App/`. The CLI parses argv to a `Command` ADT and forwards wallet/chain work to the daemon.

`LeanKohaku.lean` is import-only and re-exports every module, so downstream code writes `import LeanKohaku`.

### Sidecars (`bridge/`)

Three untrusted Node sidecars live outside the Lean tree. Each is one-shot stdio JSON-RPC, spawned per call by the daemon. The Lean-side spawn modules are the **only** places that fork them:

| Sidecar | Lean wrapper | Purpose | Trusted for? |
|---|---|---|---|
| `bridge/` | `LeanKohaku/Privacy/Bridge.lean` | Privacy Pools / Railgun (snarkjs, libp2p) | Witness generation; **not** tx structure |
| `bridge/clearsign/` | `LeanKohaku/Clearsign/Bridge.lean` | ERC-7730 calldata + EIP-712 walker | UI rendering only |
| `bridge/llm/` | `LeanKohaku/LlmAgent/Bridge.lean` | NL → tx-draft candidates (Anthropic SDK + viem) | UI suggestion only |

The trust model is uniform: **every sidecar is treated as malicious**. The daemon never signs based on a sidecar's output. Drafted txs flow through the daemon's `tx.decodeIntent` + `tx.simulate` and a TUI `ConfirmGate` before any `eoa.send` / `r1.send*` happens. Sidecars can read chain state through the daemon (`bridge/llm/src/daemon-callback.mjs` opens UDS back to the daemon's socket) but every read is policy-gated by `Privacy.NetworkPolicy` exactly like CLI/TUI requests.

Adding a new daemon-callback tool in the LLM sidecar: encode calldata via viem, call through `chain.ethCall` (the general policy-gated `eth_call` primitive). No per-protocol daemon RPC needed; see `get_aave_health_factor`, `get_uniswap_v3_quote`, and `get_morpho_blue_position` in `bridge/llm/src/anthropic-agent.mjs` as templates.

### Pre-sign pipeline

Every signing flow (TUI Send, SendRawFlow from the LLM agent, the manual Decode screen) goes through the same gate before reaching `eoa.send`:

```
  build {to, value, data}
        ↓
  tx.decodeIntent  ──→  ERC-7730 descriptor (or 4byte fallback) → human intent
        ↓
  tx.simulate      ──→  eth_call + eth_estimateGas + (opt) debug_traceCall
        ↓                    └→ daemon walks trace, prefetches token meta,
        ↓                       returns transfers → TransfersBlock renders
        ↓                       "0.1 USDC" with proper decimals
  ConfirmGate      ──→  user inspects intent + sim outcome + token movements
        ↓                    Esc bails; Enter advances
  eoa.send / r1.send*  ──→  signs and broadcasts
```

If you're adding a new "produces calldata" surface (a new dApp integration, a new agent tool, a paste-raw flow), wire it through this gate — never call `eoa.send` directly. The `SendRawFlow` component is the canonical reusable confirm path.

### Thin CLI

Per CLAUDE.md the CLI is a JSON-RPC forwarder. Wallet file I/O, account formatting, and preflight all live daemon-side now (`account.getDefault/setDefault`, `account.list`, `daemon.preflight`). Only interactive prompts (e.g. the Y/N after `tpm.create`) intentionally stay CLI-side. When adding a new command, the test is: does it manipulate state? If so, the daemon owns it, the CLI is a printer.

## Invariants workflow

`INVARIANTS.md` is the living source of truth for properties the wallet must satisfy. Every invariant is tagged 📝 stated → 🚧 in-progress → ✅ proved (or 🔒 axiomatized for FFI boundaries). The workflow when adding a new property:

1. Add an informal statement in `INVARIANTS.md`.
2. Formalize it under `LeanKohaku/Invariants/<Topic>.lean` (create the module if absent).
3. Add the theorem with a real proof before merging; no `sorry` lands in the tree.
4. Flip to ✅ and cite the theorem name + module in `INVARIANTS.md`.

Currently proved: **1.1** (`subChecked_preserves_total` in `Invariants/Amount.lean`) and **1.2** (three theorems in `Invariants/Wallet.lean` — `apply_some_affordable`, `apply_sender_debited`, `apply_non_sender_balance`). **2.1** and **2.3** are `wellFormed`-by-definition in `Invariants/TxWellFormed.lean`.

The `Invariants/Wallet.lean` abstract wallet (`State`, `Output`, `Send`, `apply`) is deliberately thin — `AccountId` is a `String`, balances are `Nat`, there is no crypto. Operational wallet types in `LeanKohaku/Wallet/` and `LeanKohaku/Ethereum/` will eventually refine these. Keep that separation: the abstract model exists to make proofs tractable, not to be the runtime.

Use `Option`-returning checked arithmetic (`Amount.subChecked`) rather than raw `Nat.sub` for any balance computation — silent clamping to zero would be a catastrophic accounting bug and invariant 1.1 exists precisely to rule it out.
