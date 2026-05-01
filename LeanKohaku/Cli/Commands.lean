import LeanKohaku.Cli.DaemonClient
import LeanKohaku.Cli.Passphrase
import LeanKohaku.Encoding.Json
import LeanKohaku.Network.Endpoint
import LeanKohaku.Network.Provider

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

/-! ## Input validation and local daemon preflight -/

def strip0x : String → String
  | s =>
      match s.toList with
      | '0' :: 'x' :: rest => String.ofList rest
      | '0' :: 'X' :: rest => String.ofList rest
      | _ => s

def hexDigit? (c : Char) : Option Nat :=
  if '0' ≤ c && c ≤ '9' then
    some (c.toNat - '0'.toNat)
  else if 'a' ≤ c && c ≤ 'f' then
    some (10 + c.toNat - 'a'.toNat)
  else if 'A' ≤ c && c ≤ 'F' then
    some (10 + c.toNat - 'A'.toNat)
  else
    none

def allHexChars : List Char → Bool
  | [] => true
  | c :: cs =>
      match hexDigit? c with
      | some _ => allHexChars cs
      | none => false

partial def decodeHexChars : List Char → ByteArray → Option ByteArray
  | [], acc => some acc
  | hi :: lo :: rest, acc => do
      let h ← hexDigit? hi
      let l ← hexDigit? lo
      decodeHexChars rest (acc.push (UInt8.ofNat (h * 16 + l)))
  | [_], _ => none

def decodeHex (s : String) : Option ByteArray :=
  decodeHexChars (strip0x s).toList ByteArray.empty

def hexChar (n : Nat) : Char :=
  match n with
  | 0 => '0' | 1 => '1' | 2 => '2' | 3 => '3'
  | 4 => '4' | 5 => '5' | 6 => '6' | 7 => '7'
  | 8 => '8' | 9 => '9' | 10 => 'a' | 11 => 'b'
  | 12 => 'c' | 13 => 'd' | 14 => 'e' | _ => 'f'

def encodeHex (bytes : ByteArray) : String :=
  "0x" ++ String.ofList (bytes.toList.foldr (fun b acc =>
    let n := b.toNat
    hexChar (n / 16) :: hexChar (n % 16) :: acc) [])

def byteArrayTake (bytes : ByteArray) (start len : Nat) : ByteArray :=
  (List.range len).foldl
    (init := ByteArray.empty)
    (fun acc i => acc.push bytes[start + i]!)

def bytesToNat (bytes : ByteArray) : Nat :=
  bytes.foldl (init := 0) (fun acc byte => acc * 256 + byte.toNat)

inductive ERC20Call where
  | transfer (to : ByteArray) (amount : Nat)
  | approve (spender : ByteArray) (amount : Nat)
  | transferFrom (fromAddr to : ByteArray) (amount : Nat)
  | unknown (selector : ByteArray)

def selectorBytes (hex : String) : ByteArray :=
  (decodeHex hex).getD ByteArray.empty

def decodeAddressWord (word : ByteArray) : Option ByteArray :=
  if word.size = 32 then
    some (byteArrayTake word 12 20)
  else
    none

def decodeERC20Call (calldata : ByteArray) : Option ERC20Call :=
  if calldata.size < 4 then
    none
  else
    let selector := byteArrayTake calldata 0 4
    if selector = selectorBytes "a9059cbb" && calldata.size ≥ 68 then
      match decodeAddressWord (byteArrayTake calldata 4 32) with
      | some to => some (.transfer to (bytesToNat (byteArrayTake calldata 36 32)))
      | none => none
    else if selector = selectorBytes "095ea7b3" && calldata.size ≥ 68 then
      match decodeAddressWord (byteArrayTake calldata 4 32) with
      | some spender => some (.approve spender (bytesToNat (byteArrayTake calldata 36 32)))
      | none => none
    else if selector = selectorBytes "23b872dd" && calldata.size ≥ 100 then
      match decodeAddressWord (byteArrayTake calldata 4 32), decodeAddressWord (byteArrayTake calldata 36 32) with
      | some fromAddr, some to => some (.transferFrom fromAddr to (bytesToNat (byteArrayTake calldata 68 32)))
      | _, _ => none
    else
      some (.unknown selector)

def ERC20Call.riskLabel : ERC20Call → String
  | .transfer _ _ => "ERC20 transfer"
  | .approve _ amount =>
      if amount = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff then
        "HIGH RISK: unlimited ERC20 approval"
      else
        "ERC20 approval"
  | .transferFrom _ _ _ => "HIGH RISK: ERC20 transferFrom"
  | .unknown _ => "unknown contract call"

def validAddressString (s : String) : Bool :=
  let raw := strip0x s
  raw.toList.length = 40 && allHexChars raw.toList

def parsePositiveNat (s : String) : Option Nat :=
  match s.toNat? with
  | some n => if n > 0 then some n else none
  | none => none

theorem parsePositiveNat_some_positive {s : String} {n : Nat} :
    parsePositiveNat s = some n → n > 0 := by
  intro h
  unfold parsePositiveNat at h
  cases hs : s.toNat? with
  | none =>
      simp [hs] at h
  | some parsed =>
      by_cases hp : parsed > 0
      · simp [hs, hp] at h
        subst h
        exact hp
      · simp [hs, hp] at h

inductive Action where
  | balance (address : String)
  | send (to : String) (amountWei : Nat)
  deriving Repr, DecidableEq

def Action.valid : Action → Bool
  | .balance address => validAddressString address
  | .send to amountWei => validAddressString to && amountWei > 0

def daemonRequest (_action : Action) : NetworkRequest :=
  { peer := .localDaemon, purpose := .daemonControl, transport := .loopback }

def preflight (policy : Policy) (action : Action) : Bool :=
  action.valid && policy (daemonRequest action)

def parseBalance (address : String) : Option Action :=
  let action := Action.balance address
  if action.valid then some action else none

def parseSend (to amount : String) : Option Action := do
  let amountWei ← parsePositiveNat amount
  let action := Action.send to amountWei
  if action.valid then some action else none

def actionSummary : Action → String
  | .balance address => s!"balance address={address}"
  | .send to amountWei => s!"send to={to} amountWei={amountWei}"

structure DaemonRequest where
  action : Action
  deriving Repr, DecidableEq

inductive Plan where
  | provider (cfg : Config) (op : Operation)
  deriving Repr, DecidableEq

def providerOperation : Action → Operation
  | .balance _ => { method := .getBalance }
  | .send _ _ => { method := .sendRawTransaction }

def strictPlan (req : DaemonRequest) : Plan :=
  .provider Config.local (providerOperation req.action)

def torPlan (req : DaemonRequest) : Plan :=
  .provider Config.torConfigured (providerOperation req.action)

def planPermitted (policy : Policy) : Plan → Bool
  | .provider cfg op => permitted policy cfg op

def strictPermitted (req : DaemonRequest) : Bool :=
  planPermitted strictDaemonPolicy (strictPlan req)

def strictCliPreflight (action : Action) : Bool :=
  preflight strictCliPolicy action

def torPermitted (req : DaemonRequest) : Bool :=
  planPermitted torDaemonPolicy (torPlan req)

def planSummary : Plan → String
  | .provider cfg op =>
      let req := requestFor cfg op
      s!"backend={cfg.backend.asString} method={op.method.asString} peer={req.peer.asString} purpose={req.purpose.asString} transport={req.transport.asString}"

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
  | walletSendSepolia (keyName : String) (to : String) (amountWei : String)
  | network
  | security
  | doctor
  | policyCheck (policy peer purpose transport : String)
  | rpcCheck (policy backend transport method : String)
  | rpcMethods
  | endpointCheck (mode kind scheme transport credentialed : String)
  | decodeErc20 (calldata : String)
  | daemonHelp (walletName : Option String)
  | daemonPing
  | daemonVersion
  | daemonStop
  | daemonWalletSend (walletName chain to amountEth : String)
  | daemon      -- run the daemon (same as `leankohaku-daemon`)
  | eoaList
  | eoaCreate (name : String) (path? : Option String)
  | eoaImport (name mnemonic : String) (path? : Option String)
  | eoaShow (name : String)
  | eoaAddress (name : String)
  | eoaUnlock (name : String)
  | eoaLock (name : String)
  | eoaDelete (name : String)
  | eoaDerive (name path : String)
  | eoaSignDigest (name digest : String)
  | eoaSignMessage (name message : String) (path? : Option String)
  | eoaSignTx (name txJson : String) (path? : Option String)
  | eoaSend (name to value : String) (data? : Option String)
  | balance (address : String)
  | nonce (address : String)
  | tokenBalance (token owner : String)
  | gasPrice
  | priorityFee
  | estimateGas (txJson : String)
  | broadcast (rawTx : String)
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
  | ["wallet", "send", "sepolia", to, amountWei] => .walletSendSepolia "sepolia-r1" to amountWei
  | ["wallet", "send", "sepolia", keyName, to, amountWei] => .walletSendSepolia keyName to amountWei
  | ["network"]           => .network
  | ["security"]          => .security
  | ["doctor"]            => .doctor
  | ["policy-check", policy, peer, purpose, transport] =>
      .policyCheck policy peer purpose transport
  | ["rpc-check", policy, backend, transport, method] =>
      .rpcCheck policy backend transport method
  | ["rpc-methods"]       => .rpcMethods
  | ["decode", "erc20", calldata] => .decodeErc20 calldata
  | ["endpoint-check", mode, kind, scheme, transport, credentialed] =>
      .endpointCheck mode kind scheme transport credentialed
  | ["daemon", "help"] => .daemonHelp none
  | ["daemon", "ping"] => .daemonPing
  | ["daemon", "version"] => .daemonVersion
  | ["daemon", "stop"] => .daemonStop
  | ["daemon", walletName, "help"] => .daemonHelp (some walletName)
  | ["daemon", walletName, "send", chain, to, amountEth] =>
      .daemonWalletSend walletName chain to amountEth
  | ["daemon"]            => .daemon
  | ["eoa", "list"] => .eoaList
  | ["eoa", "create", name] => .eoaCreate name none
  | ["eoa", "create", name, path] => .eoaCreate name (some path)
  | ["eoa", "import", name, mnemonic] => .eoaImport name mnemonic none
  | ["eoa", "import", name, path, mnemonic] => .eoaImport name mnemonic (some path)
  | ["eoa", "show", name] => .eoaShow name
  | ["eoa", "address", name] => .eoaAddress name
  | ["eoa", "unlock", name] => .eoaUnlock name
  | ["eoa", "lock", name] => .eoaLock name
  | ["eoa", "delete", name] => .eoaDelete name
  | ["eoa", "derive", name, path] => .eoaDerive name path
  | ["eoa", "sign-digest", name, digest] => .eoaSignDigest name digest
  | ["eoa", "sign-message", name, message] => .eoaSignMessage name message none
  | ["eoa", "sign-message", name, path, message] => .eoaSignMessage name message (some path)
  | ["eoa", "sign-tx", name, txJson] => .eoaSignTx name txJson none
  | ["eoa", "sign-tx", name, path, txJson] => .eoaSignTx name txJson (some path)
  | ["eoa", "send", name, to, value] => .eoaSend name to value none
  | ["eoa", "send", name, to, value, data] => .eoaSend name to value (some data)
  | ["balance", addr]     => .balance addr
  | ["nonce", addr]       => .nonce addr
  | ["token-balance", token, owner] => .tokenBalance token owner
  | ["gas-price"]         => .gasPrice
  | ["priority-fee"]      => .priorityFee
  | ["estimate-gas", txJson] => .estimateGas txJson
  | ["broadcast", rawTx]  => .broadcast rawTx
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

def erc20DecodeText (calldataHex : String) : String :=
  match decodeHex calldataHex with
  | none => "invalid hex calldata"
  | some calldata =>
      match decodeERC20Call calldata with
      | none => "not enough calldata for an ERC-20 selector"
      | some call =>
          match call with
          | .transfer to amount =>
              "ERC20 transfer\n" ++
              "risk: " ++ call.riskLabel ++ "\n" ++
              "to: " ++ encodeHex to ++ "\n" ++
              "amount: " ++ toString amount
          | .approve spender amount =>
              "ERC20 approve\n" ++
              "risk: " ++ call.riskLabel ++ "\n" ++
              "spender: " ++ encodeHex spender ++ "\n" ++
              "amount: " ++ toString amount
          | .transferFrom fromAddr to amount =>
              "ERC20 transferFrom\n" ++
              "risk: " ++ call.riskLabel ++ "\n" ++
              "from: " ++ encodeHex fromAddr ++ "\n" ++
              "to: " ++ encodeHex to ++ "\n" ++
              "amount: " ++ toString amount
          | .unknown selector =>
              "unknown contract call\nselector: " ++ encodeHex selector

def doctorText : String :=
  "leanKohaku doctor\n\n\
   Privacy/security status:\n\
     - CLI local-daemon boundary: modeled and proved\n\
     - strict daemon local-only provider policy: modeled and proved\n\
     - Tor configured-node mode: modeled and proved\n\
     - third-party/API-key endpoint denial: modeled and proved\n\
     - chain reads and raw broadcast: daemon-mediated and policy-gated\n\
     - daemon transport: Unix-domain socket with same-uid peer check\n\
     - EOA signing: daemon-only; CLI forwards JSON-RPC requests\n\n\
   Run checks:\n\
     lake build\n\
     ./script/check_privacy_cli.sh\n"

def daemonHelpText (walletName? : Option String) : String :=
  let walletName := walletName?.getD "<wallet>"
  "leanKohaku daemon wallet commands\n\n\
   Primary command shape:\n\
     leankohaku daemon <wallet> send <chain> <to> <eth>\n\n\
   Example:\n\
     leankohaku daemon " ++ walletName ++ " send sepolia 0xAa651C04bfE4F302eE243D6638d3B91389C4C02C 0.002\n\n\
   Arguments:\n\
     <wallet>  Local TPM key slot name, for example daily or sepolia-r1\n\
     <chain>   sepolia today; mainnet is intentionally disabled until production R1 deployment\n\
     <to>      20-byte Ethereum address, 0x-prefixed\n\
     <eth>     Human ETH amount, for example 0, 0.001, or 0.002\n\n\
   What happens on Sepolia:\n\
     1. Read the deployed R1 account address for the wallet key\n\
     2. Convert ETH to wei locally with cast\n\
     3. Ask the R1 account for the operation digest\n\
     4. Require fprintd biometric verification, default right-index-finger, up to 3 tries\n\
     5. Sign the digest with the local TPM P-256 key\n\
     6. Broadcast execute(...) through the deployed R1 account\n\n\
   Setup commands:\n\
     leankohaku wallet create sepolia " ++ walletName ++ "\n\
     LEAN_KOHAKU_TPM_KEY=" ++ walletName ++ " ./script/r1_sepolia.sh deploy\n\n\
   Inspect:\n\
     leankohaku wallet list sepolia\n\
     ./script/r1_sepolia.sh address\n\n\
   Safety notes:\n\
     - The TPM private blob stays local under .leankohaku/ and is gitignored\n\
     - Fingerprint verification gates signing but is not yet a TPM policy session\n\
     - The current Sepolia contract is a temporary Solidity fallback\n\
     - Contracts/R1Account/ remains the Lean/Verity source of truth\n"

def lightclientText : String :=
  "leanKohaku provider policy plan\n\n\
   Provider model:\n\
     - represents provider operations as Lean data before transport exists\n\
     - classifies methods by peer, purpose, and transport\n\
     - treats local node and future light-client reads as local policy paths\n\
     - separates transaction broadcast from read-only chain queries\n\n\
   Privacy constraints:\n\
     - no third-party APIs for discovery, metadata, analytics, or prices\n\
     - no direct CLI node calls; the daemon owns provider access\n\
     - Tor mode may read and broadcast through a configured node over Tor\n\
     - configured-node access requires explicit Tor policy\n\n\
   See LeanKohaku.Network.Provider and LeanKohaku.Invariants.Network.\n"

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
   MAIN COMMANDS:\n\
     daemon help                         Detailed wallet daemon help\n\
     daemon <wallet> send <chain> <to> <eth>\n\
                                         Send from a named TPM/R1 wallet\n\
     daemon                              Start the daemon process\n\n\
   SETUP / INSPECT:\n\
     wallet create sepolia <wallet>      Create a local TPM-backed Sepolia key\n\
     wallet list sepolia                 List local TPM-backed Sepolia keys\n\
     eoa create <name> [path]            Create an encrypted EOA slot\n\
     eoa import <name> [path] <words>    Import a BIP-39 mnemonic as an EOA slot\n\
     eoa list | show <name> | address <name>\n\
     eoa unlock <name> | lock <name> | delete <name>\n\
     eoa derive <name> <path>\n\
     eoa sign-digest <name> <32-byte-hex>\n\
     eoa sign-message <name> [path] <hex-message>\n\
     eoa sign-tx <name> [path] <tx-json>\n\
     eoa send <name> <to> <wei> [data]  Sign and broadcast ETH transfer\n\
     nonce <address>                    Read pending transaction count\n\
     token-balance <token> <owner>       Read ERC-20 balanceOf(owner)\n\
     gas-price                          Read eth_gasPrice\n\
     priority-fee                       Read eth_maxPriorityFeePerGas\n\
     estimate-gas <tx-json>             Run eth_estimateGas\n\
     broadcast <raw-tx>                 Submit a signed raw transaction\n\
     doctor                              Print implementation/check status\n\n\
   POLICY / DEBUG:\n\
     privacy | network | security | rpc-methods\n\
     policy-check <policy> <peer> <purpose> <transport>\n\
     rpc-check <policy> <backend> <transport> <method>\n\
     endpoint-check <mode> <kind> <scheme> <transport> <credentialed>\n\n\
     decode erc20 <calldata>\n\n\
   LOW-LEVEL COMPATIBILITY:\n\
     wallet sign sepolia <wallet> <digest>\n\
     wallet send sepolia <wallet> <to> <wei>\n\
     balance <address>\n\
     broadcast <raw-tx>\n\n\
   Run `leankohaku daemon help` for the documented send flow.\n"

end LeanKohaku.Cli.Commands
