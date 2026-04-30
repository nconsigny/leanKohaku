import LeanKohaku.Privacy.NetworkPolicy

/-!
# Daemon server

Long-running process that exposes wallet operations over a local socket.
The daemon is the only component allowed to perform Ethereum node I/O, and
every attempted connection must pass `Privacy.NetworkPolicy`.
-/

namespace LeanKohaku.Daemon.Server

open LeanKohaku.Privacy.NetworkPolicy

structure Config where
  socketPath : String
  chainId    : Nat
  policy     : Policy

instance : Repr Config where
  reprPrec cfg _ :=
    "Config(socketPath := " ++ repr cfg.socketPath ++
      ", chainId := " ++ repr cfg.chainId ++
      ", policy := <function>)"

def defaultConfig : Config :=
  { socketPath := "/tmp/leankohaku.sock",
    chainId := 1,
    policy := strictDaemonPolicy }

def run (_cfg : Config) : IO Unit := do
  IO.println "leankohaku-daemon: not yet implemented"

end LeanKohaku.Daemon.Server
