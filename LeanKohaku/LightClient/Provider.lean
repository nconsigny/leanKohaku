import LeanKohaku.Privacy.NetworkPolicy

/-!
# Light-client provider interface

This module mirrors the shape of `@kohaku-eth/provider` without taking a
runtime dependency on the TypeScript SDK. The upstream package wraps raw,
Helios, Colibri, Ethers, and Viem providers behind one provider contract.

For leanKohaku, the provider contract is data-first and policy-gated:
operations are classified before any transport is implemented, and Helios
style light-client reads are modeled separately from transaction broadcast.
-/

namespace LeanKohaku.LightClient.Provider

open LeanKohaku.Privacy.NetworkPolicy

inductive Backend where
  | rawLocalNode
  | heliosLightClient
  deriving DecidableEq, Repr

inductive RpcMethod where
  | chainId
  | blockNumber
  | getBalance
  | getCode
  | getLogs
  | getTransactionReceipt
  | call
  | estimateGas
  | gasPrice
  | sendRawTransaction
  deriving DecidableEq, Repr

def RpcMethod.asString : RpcMethod → String
  | .chainId => "eth_chainId"
  | .blockNumber => "eth_blockNumber"
  | .getBalance => "eth_getBalance"
  | .getCode => "eth_getCode"
  | .getLogs => "eth_getLogs"
  | .getTransactionReceipt => "eth_getTransactionReceipt"
  | .call => "eth_call"
  | .estimateGas => "eth_estimateGas"
  | .gasPrice => "eth_gasPrice"
  | .sendRawTransaction => "eth_sendRawTransaction"

def RpcMethod.purpose : RpcMethod → Purpose
  | .sendRawTransaction => .broadcastTx
  | _ => .nodeRead

/-- Minimal operation descriptor; params stay opaque until JSON is implemented. -/
structure Operation where
  method : RpcMethod
  params : List String := []
  deriving Repr

structure Config where
  backend : Backend
  chainId : Nat
  transport : Transport := .loopback
  allowLogBypass : Bool := false
  deriving Repr

def Config.defaultMainnet : Config :=
  { backend := .heliosLightClient,
    chainId := 1,
    transport := .loopback,
    allowLogBypass := false }

def Config.torMainnet : Config :=
  { backend := .heliosLightClient,
    chainId := 1,
    transport := .tor,
    allowLogBypass := false }

/--
Classify which peer an operation would need.

Helios-style reads are treated as local-node reads at this abstraction
level: the wallet must run or embed the light client locally. Broadcasts
go to an explicitly configured node so they can be separated from reads.
-/
def peerFor (cfg : Config) (op : Operation) : Peer :=
  match cfg.backend, cfg.transport, op.method with
  | _, _, .sendRawTransaction => .configuredNode
  | .rawLocalNode, _, _ => .localNode
  | .heliosLightClient, .loopback, _ => .localNode
  | .heliosLightClient, .tor, _ => .configuredNode
  | .heliosLightClient, .direct, _ => .configuredNode

def requestFor (cfg : Config) (op : Operation) : NetworkRequest :=
  { peer := peerFor cfg op, purpose := op.method.purpose, transport := cfg.transport }

def permitted (policy : Policy) (cfg : Config) (op : Operation) : Bool :=
  policy (requestFor cfg op)

/--
Direct `eth_getLogs` bypasses are risky because they can silently turn a
light-client flow into broad execution-RPC querying. Only allow the bypass
when the caller explicitly enables it and the classified request is still
accepted by the supplied policy.
-/
def permittedLogBypass (policy : Policy) (cfg : Config) : Bool :=
  cfg.allowLogBypass &&
    policy { peer := .localNode, purpose := Purpose.nodeRead, transport := .loopback }

end LeanKohaku.LightClient.Provider
