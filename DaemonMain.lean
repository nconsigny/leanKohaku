import LeanKohaku

def main (_args : List String) : IO UInt32 := do
  LeanKohaku.Daemon.Server.run LeanKohaku.Daemon.Server.defaultConfig
  return 0
