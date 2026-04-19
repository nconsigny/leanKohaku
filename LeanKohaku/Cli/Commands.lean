/-!
# CLI commands

The CLI is the primary user surface. It speaks to the daemon over the
local socket; without a running daemon, commands that need RPC fail
fast with a clear error.
-/

namespace LeanKohaku.Cli.Commands

inductive Command where
  | help
  | version
  | daemon      -- run the daemon (same as `leankohaku-daemon`)
  | balance (address : String)
  | send (to : String) (amount : String)
  deriving Repr

def parse : List String → Command
  | []                    => .help
  | ["help"]              => .help
  | ["--help"]            => .help
  | ["-h"]                => .help
  | ["version"]           => .version
  | ["--version"]         => .version
  | ["daemon"]            => .daemon
  | ["balance", addr]     => .balance addr
  | ["send", to, amount]  => .send to amount
  | _                     => .help

def helpText : String :=
  "leankohaku — formally-verified Ethereum wallet (Lean 4)\n\n\
   USAGE:\n\
     leankohaku <command> [args]\n\n\
   COMMANDS:\n\
     help                      Show this help\n\
     version                   Print version\n\
     daemon                    Start the wallet daemon\n\
     balance <address>         Fetch balance via the daemon\n\
     send <to> <amount>        Send ETH via the daemon (prompts for confirm)\n"

end LeanKohaku.Cli.Commands
