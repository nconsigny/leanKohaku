/-!
# Daemon server

Long-running process that exposes wallet operations over a local socket.
Protocol will mirror the TS `kohaku-daemon` REST/WS surface where it makes
sense. Transport starts as line-delimited JSON on a Unix domain socket;
we move to proper HTTP once we have a Lean HTTP server (or FFI to one).
-/

namespace LeanKohaku.Daemon.Server

structure Config where
  socketPath : String
  chainId    : Nat
  deriving Repr

def defaultConfig : Config :=
  { socketPath := "/tmp/leankohaku.sock", chainId := 11155111 }

def run (_cfg : Config) : IO Unit := do
  IO.println "leankohaku-daemon: not yet implemented"

end LeanKohaku.Daemon.Server
