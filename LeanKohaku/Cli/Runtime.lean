import LeanKohaku.Basic
import LeanKohaku.Cli.Commands
import LeanKohaku.Cli.DaemonClient
import LeanKohaku.Cli.Passphrase
import LeanKohaku.Encoding.Json

/-!
# CLI runtime

Thin command executor. Wallet, keystore, signing, and chain operations are
forwarded to the daemon over JSON-RPC.
-/

namespace LeanKohaku.Cli

open LeanKohaku.Cli.Commands

def printPreflight (action : Action) : IO UInt32 := do
  if strictCliPreflight action then
    let daemonReq : DaemonRequest := { action }
    let plan := strictPlan daemonReq
    IO.println s!"preflight OK: {actionSummary action}"
    IO.println "network: local-daemon daemon-control loopback"
    IO.println s!"daemon-plan: {planSummary plan}"
    IO.println "preflight only; use daemon-backed wallet commands for execution"
    return 1
  else
    IO.eprintln s!"preflight denied: {actionSummary action}"
    return 2

def runSepoliaWalletCreate (keyName : String) : IO UInt32 := do
  DaemonClient.printTextResult "tpm.createSepolia" (.obj #[("name", .str keyName)])

def runSepoliaWalletList : IO UInt32 := do
  DaemonClient.printTextResult "tpm.listSepolia"

def runSepoliaWalletSign (keyName : String) (digestHex : String) : IO UInt32 := do
  DaemonClient.printTextResult "tpm.signSepolia"
    (.obj #[("name", .str keyName), ("digest", .str digestHex)])

def runSepoliaWalletSend (keyName to amountWei : String) : IO UInt32 := do
  DaemonClient.printTextResult "r1.sendSepolia"
    (.obj #[("name", .str keyName), ("to", .str to), ("amountWei", .str amountWei)])

def runDaemonWalletSend (walletName chain to amountEth : String) : IO UInt32 := do
  match chain with
  | "sepolia" =>
      DaemonClient.printTextResult "r1.sendEthSepolia"
        (.obj #[("name", .str walletName), ("to", .str to), ("amountEth", .str amountEth)])
  | "mainnet" =>
      IO.eprintln "mainnet R1 send is not enabled yet; deploy and verify the account path on Sepolia first"
      return 2
  | _ =>
      IO.eprintln s!"unsupported chain: {chain} (expected sepolia or mainnet)"
      return 2

def runDaemonForeground : IO UInt32 := do
  let bin ←
    match ← IO.getEnv "LEANKOHAKU_DAEMON_BIN" with
    | some path => pure path
    | none => pure "leankohaku-daemon"
  let child ← IO.Process.spawn
    { cmd := bin,
      stdin := .inherit,
      stdout := .inherit,
      stderr := .inherit }
  child.wait

private def withOptionalPath (fields : Array (String × LeanKohaku.Encoding.Json.Json))
    (path? : Option String) : LeanKohaku.Encoding.Json.Json :=
  match path? with
  | none => .obj fields
  | some path => .obj (fields.push ("path", .str path))

private def withOptionalDerivationPath (fields : Array (String × LeanKohaku.Encoding.Json.Json))
    (path? : Option String) : LeanKohaku.Encoding.Json.Json :=
  match path? with
  | none => .obj fields
  | some path => .obj (fields.push ("derivationPath", .str path))

private def eoaCreate (name : String) (path? : Option String) : IO UInt32 := do
  let passphrase ← Passphrase.read
  DaemonClient.printCall "eoa.create"
    (withOptionalDerivationPath #[
      ("name", .str name),
      ("passphrase", .str passphrase)
    ] path?)

private def eoaImport (name mnemonic : String) (path? : Option String) : IO UInt32 := do
  let passphrase ← Passphrase.read
  DaemonClient.printCall "eoa.import"
    (withOptionalDerivationPath #[
      ("name", .str name),
      ("mnemonic", .str mnemonic),
      ("passphrase", .str passphrase)
    ] path?)

private def eoaUnlock (name : String) : IO UInt32 := do
  let passphrase ← Passphrase.read
  DaemonClient.printCall "eoa.unlock"
    (.obj #[("name", .str name), ("passphrase", .str passphrase)])

private def eoaDelete (name : String) : IO UInt32 := do
  let passphrase ← Passphrase.read "Passphrase for delete: "
  DaemonClient.printCall "eoa.delete"
    (.obj #[("name", .str name), ("passphrase", .str passphrase)])

private def eoaSignMessage (name message : String) (path? : Option String) : IO UInt32 :=
  DaemonClient.printCall "eoa.signMessage"
    (withOptionalPath #[
      ("name", .str name),
      ("message", .str message)
    ] path?)

private def eoaSignTx (name txJson : String) (path? : Option String) : IO UInt32 := do
  match LeanKohaku.Encoding.Json.parse txJson with
  | .error err =>
      IO.eprintln s!"invalid transaction JSON: {err}"
      return 2
  | .ok tx =>
      DaemonClient.printCall "eoa.signTx"
        (withOptionalPath #[
          ("name", .str name),
          ("tx", tx)
        ] path?)

def run (args : List String) : IO UInt32 := do
  match parse args with
  | .help       => IO.println helpText; return 0
  | .version    => IO.println s!"leankohaku {LeanKohaku.version}"; return 0
  | .privacy    => IO.println privacyText; return 0
  | .lightclient => IO.println lightclientText; return 0
  | .keystore   => IO.println keystoreText; return 0
  | .accounts   => IO.println accountsText; return 0
  | .walletCreateSepolia keyName => runSepoliaWalletCreate keyName
  | .walletListSepolia => runSepoliaWalletList
  | .walletSignSepolia keyName digestHex => runSepoliaWalletSign keyName digestHex
  | .walletSendSepolia keyName to amountWei => runSepoliaWalletSend keyName to amountWei
  | .network    => IO.println networkText; return 0
  | .security   => IO.println securityText; return 0
  | .doctor     => IO.println doctorText; return 0
  | .policyCheck policy peer purpose transport =>
      IO.println (policyCheckText policy peer purpose transport)
      return 0
  | .rpcCheck policy backend transport method =>
      IO.println (rpcCheckText policy backend transport method)
      return 0
  | .rpcMethods => IO.println rpcMethodsText; return 0
  | .decodeErc20 calldata =>
      IO.println (erc20DecodeText calldata)
      return 0
  | .endpointCheck mode kind scheme transport credentialed =>
      IO.println (endpointCheckText mode kind scheme transport credentialed)
      return 0
  | .daemonHelp walletName? =>
      IO.println (daemonHelpText walletName?)
      return 0
  | .daemonPing =>
      DaemonClient.printCall "daemon.ping"
  | .daemonVersion =>
      DaemonClient.printCall "daemon.version"
  | .daemonStop =>
      DaemonClient.printCall "daemon.shutdown"
  | .daemonWalletSend walletName chain to amountEth =>
      runDaemonWalletSend walletName chain to amountEth
  | .daemon =>
      runDaemonForeground
  | .eoaList =>
      DaemonClient.printCall "eoa.list"
  | .eoaCreate name path? =>
      eoaCreate name path?
  | .eoaImport name mnemonic path? =>
      eoaImport name mnemonic path?
  | .eoaShow name =>
      DaemonClient.printCall "eoa.show" (.obj #[("name", .str name)])
  | .eoaAddress name =>
      DaemonClient.printCall "eoa.address" (.obj #[("name", .str name)])
  | .eoaUnlock name =>
      eoaUnlock name
  | .eoaLock name =>
      DaemonClient.printCall "eoa.lock" (.obj #[("name", .str name)])
  | .eoaDelete name =>
      eoaDelete name
  | .eoaDerive name path =>
      DaemonClient.printCall "eoa.derive" (.obj #[("name", .str name), ("path", .str path)])
  | .eoaSignDigest name digest =>
      DaemonClient.printCall "eoa.signDigest" (.obj #[("name", .str name), ("digest", .str digest)])
  | .eoaSignMessage name message path? =>
      eoaSignMessage name message path?
  | .eoaSignTx name txJson path? =>
      eoaSignTx name txJson path?
  | .eoaSend name to value data? =>
      match value.toNat? with
      | none =>
          IO.eprintln s!"invalid eoa send value: {value}"
          return 2
      | some valueNat =>
          if !validAddressString to then
            IO.eprintln s!"invalid eoa send recipient: {to}"
            return 2
          else
            let fields := #[
              ("name", .str name),
              ("to", .str to),
              ("value", .num (Int.ofNat valueNat))
            ]
            let params :=
              match data? with
              | none => .obj fields
              | some data => .obj (fields.push ("data", .str data))
            DaemonClient.printCall "eoa.send" params
  | .balance a  =>
      match parseBalance a with
      | some _ =>
          DaemonClient.printCall "chain.balance" (.obj #[("address", .str a)])
      | none =>
          IO.eprintln s!"invalid balance address: {a}"
          return 2
  | .nonce a =>
      if validAddressString a then
        DaemonClient.printCall "chain.nonce" (.obj #[("address", .str a)])
      else
        IO.eprintln s!"invalid nonce address: {a}"
        return 2
  | .tokenBalance token owner =>
      if validAddressString token && validAddressString owner then
        DaemonClient.printCall "chain.tokenBalance"
          (.obj #[("token", .str token), ("owner", .str owner)])
      else
        IO.eprintln s!"invalid token-balance arguments: token={token} owner={owner}"
        return 2
  | .gasPrice =>
      DaemonClient.printCall "chain.gasPrice"
  | .priorityFee =>
      DaemonClient.printCall "chain.maxPriorityFeePerGas"
  | .estimateGas txJson =>
      match LeanKohaku.Encoding.Json.parse txJson with
      | .error err =>
          IO.eprintln s!"invalid estimate-gas transaction JSON: {err}"
          return 2
      | .ok tx =>
          DaemonClient.printCall "chain.estimateGas" (.obj #[("tx", tx)])
  | .broadcast rawTx =>
      match decodeHex rawTx with
      | some bytes =>
          if bytes.isEmpty then
            IO.eprintln "invalid raw transaction: empty hex"
            return 2
          else
            DaemonClient.printCall "chain.sendRawTransaction" (.obj #[("raw", .str rawTx)])
      | none =>
          IO.eprintln "invalid raw transaction hex"
          return 2
  | .send to amount =>
      match parseSend to amount with
      | some _ =>
          IO.eprintln "send requires a named unlocked wallet; use eoa send once chain execution is configured"
          return 2
      | none =>
          IO.eprintln s!"invalid send arguments: to={to} amountWei={amount}"
          return 2
  | .invalid args =>
      IO.eprintln s!"unknown or invalid command: {args}"
      IO.println helpText
      return 2

end LeanKohaku.Cli
