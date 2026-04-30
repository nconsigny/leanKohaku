# Privacy And Security

leanKohaku is designed around a narrow network boundary:

- The CLI talks only to the local daemon over loopback.
- Strict daemon mode uses local/light-client provider access only.
- Configured-node access requires Tor mode.
- Broadcast is limited to `eth_sendRawTransaction`.
- Endpoint configuration rejects credentialed/API-key endpoints.
- Third-party APIs are not wallet dependencies.

## Denied Surfaces

The following categories are denied by policy and should not be added as
defaults, fallbacks, or convenience features:

- Analytics and telemetry.
- Crash-report uploads.
- Price quote APIs.
- Fiat/onramp APIs.
- Metadata and indexer APIs.
- Peer discovery services.
- Hosted RPC endpoints that require API keys.
- Any direct CLI-to-node path.

## Mode Semantics

`strict` mode:

- Allows local node reads over loopback.
- Allows local raw transaction broadcast over loopback.
- Denies all configured-node traffic.
- Denies all third-party peers and third-party purposes.

`tor` mode:

- Allows local loopback provider access.
- Allows configured-node reads and broadcasts over Tor.
- Denies direct configured-node reads.
- Denies third-party peers and credentialed endpoints.

`deny` mode:

- Denies every request.

## Invariant Modules

- `LeanKohaku.Invariants.Network`

These modules prove the current policy boundaries used by the CLI and
daemon models.
