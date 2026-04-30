import LeanKohaku.Network.Provider
import LeanKohaku.Network.Endpoint

/-!
# CLI commands

The CLI is the primary user surface. It speaks to the daemon over the
local socket; without a running daemon, commands that need RPC fail
fast with a clear error.
-/

namespace LeanKohaku.Cli.Commands

open LeanKohaku.Privacy.NetworkPolicy
open LeanKohaku.Network.Provider
open LeanKohaku.Network.Endpoint

inductive Command where
  | help
  | version
  | privacy
  | lightclient
  | keystore
  | accounts
  | walletCreateSepolia (keyName : String)
  | walletListSepolia
  | walletSignSepolia (keyName : String) (digestHex : String)
  | network
  | security
  | doctor
  | policyCheck (policy peer purpose transport : String)
  | rpcCheck (policy backend transport method : String)
  | rpcMethods
  | endpointCheck (mode kind scheme transport credentialed : String)
  | daemon      -- run the daemon (same as `leankohaku-daemon`)
  | balance (address : String)
  | send (to : String) (amount : String)
  | invalid (args : List String)
  deriving Repr

def parse : List String → Command
  | []                    => .help
  | ["help"]              => .help
  | ["--help"]            => .help
  | ["-h"]                => .help
  | ["version"]           => .version
  | ["--version"]         => .version
  | ["privacy"]           => .privacy
  | ["lightclient"]       => .lightclient
  | ["keystore"]          => .keystore
  | ["accounts"]          => .accounts
  | ["wallet", "create", "sepolia"] => .walletCreateSepolia "sepolia-r1"
  | ["wallet", "create", "sepolia", "r1-smart"] => .walletCreateSepolia "sepolia-r1"
  | ["wallet", "create", "sepolia", keyName] => .walletCreateSepolia keyName
  | ["wallet", "create", "sepolia", "r1-smart", keyName] => .walletCreateSepolia keyName
  | ["wallet", "list", "sepolia"] => .walletListSepolia
  | ["wallet", "sign", "sepolia", digestHex] => .walletSignSepolia "sepolia-r1" digestHex
  | ["wallet", "sign", "sepolia", keyName, digestHex] => .walletSignSepolia keyName digestHex
  | ["network"]           => .network
  | ["security"]          => .security
  | ["doctor"]            => .doctor
  | ["policy-check", policy, peer, purpose, transport] =>
      .policyCheck policy peer purpose transport
  | ["rpc-check", policy, backend, transport, method] =>
      .rpcCheck policy backend transport method
  | ["rpc-methods"]       => .rpcMethods
  | ["endpoint-check", mode, kind, scheme, transport, credentialed] =>
      .endpointCheck mode kind scheme transport credentialed
  | ["daemon"]            => .daemon
  | ["balance", addr]     => .balance addr
  | ["send", to, amount]  => .send to amount
  | args                  => .invalid args

private def joinComma : List String → String
  | [] => ""
  | [x] => x
  | x :: xs => x ++ ", " ++ joinComma xs

private def allowDeny (b : Bool) : String :=
  if b then "ALLOW" else "DENY"

def policyCheckText (policyS peerS purposeS transportS : String) : String :=
  match parsePolicy policyS, parsePeer peerS, parsePurpose purposeS, parseTransport transportS with
  | some policy, some peer, some purpose, some transport =>
      let req : NetworkRequest := { peer, purpose, transport }
      s!"{allowDeny (policy req)} policy={policyS} peer={peer.asString} purpose={purpose.asString} transport={transport.asString}"
  | _, _, _, _ =>
      "invalid policy-check arguments\n\n\
       usage: leankohaku policy-check <policy> <peer> <purpose> <transport>\n\
       policies: " ++ joinComma policyNames ++ "\n\
       peers: " ++ joinComma peerNames ++ "\n\
       purposes: " ++ joinComma purposeNames ++ "\n\
       transports: " ++ joinComma transportNames

def rpcCheckText (policyS backendS transportS methodS : String) : String :=
  match parsePolicy policyS, parseBackend backendS, parseTransport transportS, parseRpcMethod methodS with
  | some policy, some backend, some transport, some method =>
      let cfg : Config := { backend, transport }
      let op : Operation := { method }
      let req := requestFor cfg op
      s!"{allowDeny (permitted policy cfg op)} policy={policyS} backend={backend.asString} method={method.asString} peer={req.peer.asString} purpose={req.purpose.asString} transport={req.transport.asString}"
  | _, _, _, _ =>
      "invalid rpc-check arguments\n\n\
       usage: leankohaku rpc-check <policy> <backend> <transport> <rpc-method>\n\
       policies: " ++ joinComma policyNames ++ "\n\
       backends: " ++ joinComma backendNames ++ "\n\
       transports: " ++ joinComma transportNames ++ "\n\
       methods: " ++ joinComma rpcMethodNames

def endpointCheckText (modeS kindS schemeS transportS credentialedS : String) : String :=
  match parseEndpointKind kindS, parseScheme schemeS, parseTransport transportS, parseBool credentialedS with
  | some kind, some scheme, some transport, some credentialed =>
      let ep : Endpoint := { kind, scheme, transport, credentialed }
      let allowed :=
        match modeS with
        | "strict" => acceptedStrict ep
        | "tor" => acceptedTor ep
        | _ => false
      s!"{allowDeny allowed} mode={modeS} endpoint-kind={kind.asString} scheme={scheme.asString} transport={transport.asString} credentialed={credentialed}"
  | _, _, _, _ =>
      "invalid endpoint-check arguments\n\n\
       usage: leankohaku endpoint-check <strict|tor> <kind> <scheme> <transport> <credentialed>\n\
       kinds: " ++ joinComma kindNames ++ "\n\
       schemes: " ++ joinComma schemeNames ++ "\n\
       transports: " ++ joinComma transportNames ++ "\n\
       credentialed: true, false"

def privacyText : String :=
  "leanKohaku privacy policy\n\n\
   CLI:\n\
     - only local daemon control over loopback is allowed\n\
     - direct node, indexer, analytics, price, fiat, metadata, discovery, and crash-report calls are denied\n\n\
   Daemon:\n\
     - local/light-client reads use loopback\n\
     - local transaction broadcast uses loopback\n\
     - configured-node traffic is denied in strict mode\n\
     - Tor mode may read or broadcast through a configured node over Tor\n\
     - third-party APIs remain denied even when Tor is enabled\n\n\
   Policy modules: LeanKohaku.Privacy.NetworkPolicy, LeanKohaku.Network.Provider.\n"

def networkText : String :=
  "leanKohaku network surface\n\n\
   Allowed JSON-RPC purposes:\n\
     - nodeRead: chain id, block number, balance, nonce, code, call, gas estimation, fee data\n\
     - broadcastTx: eth_sendRawTransaction only\n\n\
   Denied surfaces:\n\
     - peer discovery\n\
     - analytics and telemetry\n\
     - price quotes and fiat onramps\n\
     - metadata lookups and indexer APIs\n\
     - crash-report uploads\n\
     - any unclassified transport path\n"

def securityText : String :=
  "leanKohaku security posture\n\n\
   Hard rules:\n\
     - deny by default\n\
     - CLI never talks to nodes or third-party services\n\
     - strict daemon mode is local/light-client only\n\
     - configured-node access requires Tor mode\n\
     - only eth_sendRawTransaction is a broadcast purpose\n\
     - no analytics, telemetry, price APIs, fiat/onramp APIs, indexers, metadata lookup, peer discovery, or crash uploads\n\n\
   Useful checks:\n\
     leankohaku policy-check strict configured-node broadcast-tx direct\n\
     leankohaku policy-check tor configured-node node-read tor\n\
     leankohaku rpc-check strict configured direct eth_getBalance\n\
     leankohaku rpc-check tor configured tor eth_sendRawTransaction\n\
     leankohaku endpoint-check strict local http loopback false\n\
     leankohaku endpoint-check tor configured onion tor false\n"

def rpcMethodsText : String :=
  "allowed modeled JSON-RPC methods:\n" ++ joinComma rpcMethodNames

def doctorText : String :=
  "leanKohaku doctor\n\n\
   Privacy/security status:\n\
     - CLI local-daemon boundary: modeled and proved\n\
     - strict daemon local-only provider policy: modeled and proved\n\
     - Tor configured-node mode: modeled and proved\n\
     - third-party/API-key endpoint denial: modeled and proved\n\
     - balance/send input validation and local preflight: modeled and proved\n\
     - daemon transport: not implemented, so no network I/O is attempted by wallet actions\n\n\
   Run checks:\n\
     lake build\n\
     ./script/check_privacy_cli.sh\n"

def lightclientText : String :=
  "leanKohaku light-client plan\n\n\
   Provider model:\n\
     - mirrors @kohaku-eth/provider's raw/Helios provider boundary\n\
     - represents provider operations as Lean data before transport exists\n\
     - treats Helios-style reads as local light-client reads\n\
     - separates transaction broadcast from read-only chain queries\n\n\
   Privacy constraints:\n\
     - no third-party APIs for discovery, metadata, analytics, or prices\n\
     - no direct CLI node calls; the daemon owns provider access\n\
     - Tor mode may read and broadcast through a configured node over Tor\n\
     - eth_getLogs bypass is disabled by default and must remain policy-gated\n\n\
   See LeanKohaku.LightClient.Provider and LeanKohaku.Invariants.LightClient.\n"

def keystoreText : String :=
  "leanKohaku local keystore policy\n\n\
   Boundary:\n\
     - keystore access is local-only; no online or remote keystore service\n\
     - wallet code must never receive raw private keys or seed material\n\
     - normal operations deny key import/export\n\
     - signing requires hardware-backed key custody and user authorization\n\n\
   Platform notes:\n\
     - Ethereum mainnet is production; Sepolia is explicit dev/testnet support\n\
     - macOS/iOS native Secure Enclave is modeled for P-256/R1\n\
     - Linux profiles prefer TPM2 on common HP/Lenovo hardware, with FIDO2 fallback\n\
     - the Linux kernel keyring is modeled as local handle storage, not signing\n\
     - account logic verifies R1 signatures with the P256VERIFY precompile model\n\n\
   Runtime:\n\
     - wallet create sepolia creates a local TPM2-wrapped P-256 dev key\n\
     - wallet create sepolia <name> creates an additional named TPM key\n\
     - wallet sign sepolia <name> <digest> signs a 32-byte digest locally\n\
     - new key creation requires local fprintd biometric verification\n\
     - signing requires local fprintd biometric verification\n\
     - key material is stored under .leankohaku/ and is ignored by git\n\n\
   See LeanKohaku.Keystore.Enclave, LeanKohaku.Keystore.Linux, and\n\
   LeanKohaku.Keystore.Tpm2Runtime.\n"

def accountsText : String :=
  "leanKohaku account policy\n\n\
   Supported account families:\n\
     - eoa-k1: regular BIP-39/BIP-32 Ethereum EOA with k1 signing\n\
     - r1-smart: local hardware-backed P-256/R1 account using EIP-7951 verification\n\n\
   Defaults:\n\
     - eoa-k1 path: m/44'/60'/0'/0/0\n\
     - r1-smart key source: local enclave / TPM / FIDO / Secure Enclave class backend\n\
     - chain: Ethereum mainnet by default; Sepolia is available for dev/testing\n\
     - custody: local only; no online keystore\n\n\
   See LeanKohaku.Wallet.Account and LeanKohaku.Invariants.Account.\n"

def helpText : String :=
  "leankohaku — formally-verified Ethereum wallet (Lean 4)\n\n\
   USAGE:\n\
     leankohaku <command> [args]\n\n\
   COMMANDS:\n\
     help                      Show this help\n\
     version                   Print version\n\
     privacy                   Print privacy policy\n\
     lightclient               Print the light-client provider policy\n\
     keystore                  Print the enclave keystore policy\n\
     accounts                  Print supported account policies\n\
     wallet create sepolia     Start the Sepolia R1 wallet creation flow\n\
     wallet create sepolia <name>\n\
                               Create an additional named TPM2 key slot\n\
     wallet create sepolia r1-smart\n\
                               Same as above, explicit account family\n\
     wallet list sepolia       List local Sepolia TPM2 key slots\n\
     wallet sign sepolia <digest>\n\
                               Sign a 32-byte hex digest with the default key\n\
     wallet sign sepolia <name> <digest>\n\
                               Sign with a named TPM2 key slot\n\
     network                   Print network surface policy\n\
     security                  Print strict security posture\n\
     doctor                    Print implementation/check status\n\
     policy-check <policy> <peer> <purpose> <transport>\n\
                               Evaluate a raw network policy request\n\
     rpc-check <policy> <backend> <transport> <method>\n\
                               Evaluate a modeled JSON-RPC request\n\
     rpc-methods               List modeled JSON-RPC methods\n\
     endpoint-check <mode> <kind> <scheme> <transport> <credentialed>\n\
                               Evaluate endpoint hygiene policy\n\
     daemon                    Start the wallet daemon\n\
     balance <address>         Fetch balance via the daemon\n\
     send <to> <amount>        Send ETH via the daemon (prompts for confirm)\n"

end LeanKohaku.Cli.Commands
