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
- **Privacy and security by default.** The CLI is local-only. Network
  operations are classified by peer, purpose, and transport before any I/O
  can be implemented. Third-party APIs, analytics, price feeds, metadata
  lookups, fiat/onramp calls, crash reports, and discovery are denied.
- **Tor as explicit transport.** Tor is a transport to a configured node,
  not permission to use third-party APIs.
- **Privacy-friendly later.** Railgun-style shielded-note semantics are a
  late-stage target built on top of the strict network posture.

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
│  ├─ Privacy/     NetworkPolicy
│  ├─ Network/     Provider
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
./.lake/build/bin/leankohaku privacy
./.lake/build/bin/leankohaku network
./.lake/build/bin/leankohaku security
./.lake/build/bin/leankohaku doctor
./.lake/build/bin/leankohaku policy-check strict configured-node broadcast-tx direct
./.lake/build/bin/leankohaku rpc-check tor configured tor eth_sendRawTransaction
./.lake/build/bin/leankohaku endpoint-check strict local http loopback false
./.lake/build/bin/leankohaku endpoint-check tor configured onion tor false
./.lake/build/bin/leankohaku balance 0x0000000000000000000000000000000000000000
./.lake/build/bin/leankohaku send 0x0000000000000000000000000000000000000000 1
./.lake/build/bin/leankohaku daemon    # starts the daemon (stub for now)
```

## Network Privacy

`LeanKohaku.Privacy.NetworkPolicy` is the deny-by-default boundary:

- CLI traffic is limited to local daemon control over loopback.
- Daemon reads use local/light-client loopback by default.
- Broadcast is limited to `eth_sendRawTransaction`.
- Strict mode denies configured-node traffic, including direct broadcast.
- Tor mode may read and broadcast through a configured node over Tor.
- Third-party APIs remain denied even when Tor is enabled.

Denied categories include peer discovery, analytics, telemetry, price
quotes, fiat/onramp calls, metadata/indexer APIs, crash reports, and any
unclassified transport path.

`balance` and `send` are currently preflight-functional: they validate CLI
inputs, classify the only permitted local-daemon request, and stop before
network I/O because daemon transport is still a stub. Invalid input exits
before any daemon or network path is attempted.

The daemon-side plan is also modeled:

- `balance` maps to `eth_getBalance` against the local provider.
- `send` maps to `eth_sendRawTransaction` against the local provider.
- Tor mode can later switch the provider plan to a configured node over Tor.

Endpoint hygiene is modeled separately:

- Strict mode accepts only local, uncredentialed endpoints over loopback.
- Tor mode accepts local loopback endpoints and uncredentialed configured
  endpoints over Tor.
- Credentialed endpoints are denied to prevent API-key hosted services.
- Third-party endpoints are denied in every mode.

Run the privacy CLI regression checks with:

```bash
./script/check_privacy_cli.sh
```

More detail:

- [CLI](./docs/CLI.md)
- [Privacy And Security](./docs/PRIVACY_SECURITY.md)

## Invariants

See [`INVARIANTS.md`](./INVARIANTS.md). The current proved inventory:

| # | Invariant | Status |
|---|-----------|--------|
| 1.1 | Checked subtraction preserves totals | ✅ |
| 1.2 | Multi-output send — refuse-insufficient + exact-debit + recipient crediting | ✅ |
| 2.1 | EIP-1559 fee relation | ✅ (by definition) |
| 2.3 | Chain-ID match | ✅ (by definition) |
| 5.9 | CLI wallet actions preflight only through local daemon | ✅ |
| 5.10 | Daemon action plans stay inside modeled provider operations | ✅ |
| 5.11 | Endpoint hygiene rejects credentialed and third-party endpoints | ✅ |
| 6.1 | CLI only talks to local daemon | ✅ |
| 6.2 | Daemon policies never allow third-party API peers | ✅ |
| 6.3 | Strict mode denies configured-node access | ✅ |
| 6.4 | Third-party purposes are denied | ✅ |
| everything else | — | 📝 / 🚧 |

## Relationship to upstream `kohaku-ai`

`kohaku-ai` is the reference implementation in TypeScript: LLM agent
orchestration, web UI, Tauri desktop, Railgun SDK integration. This
project borrows its domain model (wallet, swaps, shielded notes) but
rewrites the code path in Lean with a much tighter scope. No runtime
code is shared.

## License

TBD.
