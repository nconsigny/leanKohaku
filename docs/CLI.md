# CLI

The CLI is the primary wallet surface. It must not talk directly to
Ethereum nodes, indexers, analytics, price feeds, fiat/onramp APIs,
metadata services, crash-report services, or peer-discovery services.

## Commands

```bash
leankohaku help
leankohaku version
leankohaku privacy
leankohaku network
leankohaku security
leankohaku doctor
leankohaku rpc-methods
```

Policy inspection:

```bash
leankohaku policy-check strict configured-node broadcast-tx direct
leankohaku policy-check tor configured-node node-read tor
leankohaku rpc-check strict configured direct eth_getBalance
leankohaku rpc-check tor configured tor eth_sendRawTransaction
leankohaku endpoint-check strict local http loopback false
leankohaku endpoint-check tor configured onion tor false
```

Wallet-action preflight:

```bash
leankohaku balance 0x0000000000000000000000000000000000000000
leankohaku send 0x0000000000000000000000000000000000000000 1
```

These commands validate inputs and print the local daemon/provider plan.
They currently exit with code `1` after successful preflight because daemon
transport is not implemented. Invalid inputs exit with code `2` before any
daemon or network path is attempted.

Daemon wallet send:

```bash
leankohaku daemon help
leankohaku daemon daily send sepolia 0xAa651C04bfE4F302eE243D6638d3B91389C4C02C 0.002
```

This is the preferred user-facing send path. It takes ETH units, computes
the R1 account digest, requires local TPM/fingerprint signing, and then
broadcasts the R1 account `execute` transaction on Sepolia.

## Regression Check

```bash
./script/check_privacy_cli.sh
```

This script builds the project and checks representative allow/deny paths.
