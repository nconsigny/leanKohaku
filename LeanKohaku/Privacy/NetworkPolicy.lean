/-!
# Network privacy policy

The CLI and daemon should have an explicit deny-by-default model for all
network-capable operations. This module classifies every attempted
connection by peer and purpose before implementation code is allowed to
perform I/O.
-/

namespace LeanKohaku.Privacy.NetworkPolicy

/-- The class of peer a process wants to contact. -/
inductive Peer where
  | localDaemon
  | localNode
  | configuredNode
  | thirdPartyApi
  deriving DecidableEq, Repr

/-- The reason a process wants to open a connection. -/
inductive Purpose where
  | daemonControl
  | nodeRead
  | broadcastTx
  | peerDiscovery
  | analytics
  | priceQuote
  | metadataLookup
  deriving DecidableEq, Repr

inductive Transport where
  | loopback
  | tor
  | direct
  deriving DecidableEq, Repr

structure NetworkRequest where
  peer    : Peer
  purpose : Purpose
  transport : Transport := .loopback
  deriving Repr

def Policy := NetworkRequest → Bool

/--
The CLI must not contact Ethereum nodes or external services directly.
It may only speak to the local daemon transport.
-/
def strictCliPolicy : Policy
  | { peer := .localDaemon, purpose := .daemonControl, transport := .loopback } => true
  | _ => false

/--
The daemon may read from a local node and may broadcast only to a local
node or an explicitly configured node. Third-party APIs, analytics,
metadata lookups, price feeds, and peer discovery are denied.
-/
def strictDaemonPolicy : Policy
  | { peer := .localNode, purpose := .nodeRead, transport := .loopback } => true
  | { peer := .localNode, purpose := .broadcastTx, transport := .loopback } => true
  | { peer := .configuredNode, purpose := .broadcastTx, transport := .direct } => true
  | { peer := .configuredNode, purpose := .broadcastTx, transport := .tor } => true
  | _ => false

/--
Tor mode permits read and broadcast access to an explicitly configured node
only through Tor. Third-party APIs remain denied.
-/
def torDaemonPolicy : Policy
  | { peer := .localNode, purpose := .nodeRead, transport := .loopback } => true
  | { peer := .localNode, purpose := .broadcastTx, transport := .loopback } => true
  | { peer := .configuredNode, purpose := .nodeRead, transport := .tor } => true
  | { peer := .configuredNode, purpose := .broadcastTx, transport := .tor } => true
  | _ => false

/-- Deny-by-default helper for future features that have not been classified. -/
def denyByDefault : Policy := fun _ => false

end LeanKohaku.Privacy.NetworkPolicy
