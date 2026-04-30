import LeanKohaku

open LeanKohaku.Cli.Commands
open LeanKohaku.Cli.Actions
open LeanKohaku.Daemon.Protocol
open LeanKohaku.Privacy.NetworkPolicy

def printPreflight (action : Action) : IO UInt32 := do
  if preflight strictCliPolicy action then
    let daemonReq : Request := { action }
    let plan := strictPlan daemonReq
    IO.println s!"preflight OK: {actionSummary action}"
    IO.println "network: local-daemon daemon-control loopback"
    IO.println s!"daemon-plan: {planSummary plan}"
    IO.println "daemon transport is not implemented yet; no network I/O was attempted"
    return 1
  else
    IO.eprintln s!"preflight denied: {actionSummary action}"
    return 2

def main (args : List String) : IO UInt32 := do
  match parse args with
  | .help       => IO.println helpText; return 0
  | .version    => IO.println s!"leankohaku {LeanKohaku.version}"; return 0
  | .privacy    => IO.println privacyText; return 0
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
  | .endpointCheck mode kind scheme transport credentialed =>
      IO.println (endpointCheckText mode kind scheme transport credentialed)
      return 0
  | .daemon     =>
      LeanKohaku.Daemon.Server.run LeanKohaku.Daemon.Server.defaultConfig
      return 0
  | .balance a  =>
      match parseBalance a with
      | some action => printPreflight action
      | none =>
          IO.eprintln s!"invalid balance address: {a}"
          return 2
  | .send to amount =>
      match parseSend to amount with
      | some action => printPreflight action
      | none =>
          IO.eprintln s!"invalid send arguments: to={to} amountWei={amount}"
          return 2
  | .invalid args =>
      IO.eprintln s!"unknown or invalid command: {args}"
      IO.println helpText
      return 2
