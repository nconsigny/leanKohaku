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
  | privacy
  | lightclient
  | keystore
  | accounts
  | walletCreateSepolia (keyName : String)
  | walletListSepolia
  | walletSignSepolia (keyName : String) (digestHex : String)
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
  | ["daemon"]            => .daemon
  | ["balance", addr]     => .balance addr
  | ["send", to, amount]  => .send to amount
  | _                     => .help

def privacyText : String :=
  "leanKohaku privacy policy\n\n\
   CLI:\n\
     - may only speak to the local wallet daemon\n\
     - must not contact Ethereum nodes directly\n\
     - must not call third-party APIs, analytics, price feeds, or metadata services\n\n\
   Daemon:\n\
     - may read chain state only from a local node\n\
     - may broadcast signed transactions only to a local node or explicitly configured node\n\
     - may use Tor only as an explicit transport to a configured node\n\
     - must deny peer discovery, analytics, price quotes, metadata lookups, and third-party APIs\n\n\
   This policy is represented in LeanKohaku.Privacy.NetworkPolicy and backed by\n\
   LeanKohaku.Invariants.NetworkPrivacy.\n"

def lightclientText : String :=
  "leanKohaku light-client plan\n\n\
   Provider model:\n\
     - mirrors @kohaku-eth/provider's raw/Helios provider boundary\n\
     - represents provider operations as Lean data before transport exists\n\
     - treats Helios-style reads as local light-client reads\n\
     - separates transaction broadcast from read-only chain queries\n\n\
   Privacy constraints:\n\
     - no third-party APIs for discovery, metadata, analytics, or prices\n\
     - no direct CLI node calls; the daemon owns provider access\n\
     - Tor mode may read and broadcast through a configured node over Tor\n\
     - eth_getLogs bypass is disabled by default and must remain policy-gated\n\n\
   See LeanKohaku.LightClient.Provider and LeanKohaku.Invariants.LightClient.\n"

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
   COMMANDS:\n\
     help                      Show this help\n\
     version                   Print version\n\
     privacy                   Print the network privacy policy\n\
     lightclient               Print the light-client provider policy\n\
     keystore                  Print the enclave keystore policy\n\
     accounts                  Print supported account policies\n\
     wallet create sepolia     Start the Sepolia R1 wallet creation flow\n\
     wallet create sepolia <name>\n\
                               Create an additional named TPM2 key slot\n\
     wallet create sepolia r1-smart\n\
                               Same as above, explicit account family\n\
     wallet list sepolia       List local Sepolia TPM2 key slots\n\
     wallet sign sepolia <digest>\n\
                               Sign a 32-byte hex digest with the default key\n\
     wallet sign sepolia <name> <digest>\n\
                               Sign with a named TPM2 key slot\n\
     daemon                    Start the wallet daemon\n\
     balance <address>         Fetch balance via the daemon\n\
     send <to> <amount>        Send ETH via the daemon (prompts for confirm)\n"

end LeanKohaku.Cli.Commands
