# leanKohaku

A formally-verified Ethereum wallet daemon written entirely in **Lean 4**,
with a CLI-first surface. Inspired by [`kohaku-ai`][upstream] (TypeScript)
but re-architected from the ground up for machine-checked proofs of the
critical signing path.

[upstream]: https://github.com/jiayaoqijia/kohaku-ai

## Goals

- **CLI-first.** The primary interface is a local command-line tool that
  talks to a long-running daemon over a Unix domain socket.
- **Full Lean.** No FFI to Rust/JS crypto libraries. secp256k1, Keccak,
  RLP, BIP32/39, JSON-RPC — everything is implemented in Lean so it can
  be reasoned about inside the same type system.
- **Iteratively verified.** We do not aim for 100% proof coverage on day
  one. Instead we grow `INVARIANTS.md` alongside the code, and elevate
  each invariant from 📝 (stated) → 🚧 (in progress) → ✅ (proved).
- **Privacy-friendly eventually.** Railgun-style shielded-note semantics
  are a late-stage target, not an initial one.

## Non-goals (for now)

- Browser / mobile UI.
- Multi-LLM agent orchestration (the upstream's main selling point).
- Production readiness — this is a research wallet.

## Layout

```
leanKohaku/
├─ lakefile.lean                  # Lake build config
├─ lean-toolchain                 # pinned Lean version
├─ Main.lean                      # CLI entrypoint
├─ DaemonMain.lean                # Daemon entrypoint
├─ LeanKohaku.lean                # Root module (re-exports)
├─ LeanKohaku/
│  ├─ Basic.lean
│  ├─ Crypto/      Hex, Keccak, Sha256, Sha512, Secp256k1
│  ├─ Encoding/    Rlp
│  ├─ Ethereum/    Address, Chain, Tx
│  ├─ Wallet/      Mnemonic (BIP39), HDKey (BIP32)
│  ├─ RPC/         JsonRpc
│  ├─ Daemon/      Server
│  ├─ Cli/         Commands
│  └─ Invariants/  Amount, Nonce, TxWellFormed
├─ INVARIANTS.md                  # Living list of properties + proof status
└─ README.md
```

## Build

```bash
elan toolchain install $(cat lean-toolchain)  # installs Lean 4.29.1
lake build                                     # builds lib + both executables
```

Artifacts land in `.lake/build/bin/`:
- `leankohaku`         — CLI
- `leankohaku-daemon`  — daemon

## Quick start

```bash
./.lake/build/bin/leankohaku help
./.lake/build/bin/leankohaku version
./.lake/build/bin/leankohaku daemon    # starts the daemon (stub for now)
```

## Invariants

See [`INVARIANTS.md`](./INVARIANTS.md). The current proved inventory:

| # | Invariant | Status |
|---|-----------|--------|
| 1.1 | Checked subtraction preserves totals | ✅ |
| 2.1 | EIP-1559 fee relation | ✅ (by definition) |
| 2.3 | Chain-ID match | ✅ (by definition) |
| everything else | — | 📝 / 🚧 |

## Relationship to upstream `kohaku-ai`

`kohaku-ai` is the reference implementation in TypeScript: LLM agent
orchestration, web UI, Tauri desktop, Railgun SDK integration. This
project borrows its domain model (wallet, swaps, shielded notes) but
rewrites the code path in Lean with a much tighter scope. No runtime
code is shared.

## License

TBD.
