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

def helpText : String :=
  "leankohaku — formally-verified Ethereum wallet (Lean 4)\n\n\
   USAGE:\n\
     leankohaku <command> [args]\n\n\
   COMMANDS:\n\
     help                      Show this help\n\
     version                   Print version\n\
     privacy                   Print privacy policy\n\
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
