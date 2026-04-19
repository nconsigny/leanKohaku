import LeanKohaku

open LeanKohaku.Cli.Commands

def main (args : List String) : IO UInt32 := do
  match parse args with
  | .help       => IO.println helpText; return 0
  | .version    => IO.println s!"leankohaku {LeanKohaku.version}"; return 0
  | .daemon     =>
      LeanKohaku.Daemon.Server.run LeanKohaku.Daemon.Server.defaultConfig
      return 0
  | .balance a  =>
      IO.println s!"balance {a}: (not yet implemented — needs daemon + RPC)"
      return 1
  | .send to amount =>
      IO.println s!"send {amount} → {to}: (not yet implemented — needs signer)"
      return 1
