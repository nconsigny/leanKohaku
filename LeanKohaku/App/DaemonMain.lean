import LeanKohaku.Lib.Core

def main (_args : List String) : IO UInt32 := do
  LeanKohaku.Daemon.Server.run (← LeanKohaku.Daemon.Config.resolve)
  return 0
