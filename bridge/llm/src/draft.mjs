// Draft-from-intent: turn a natural-language prompt + chain context into
// one or more transaction-draft candidates ({ to, value, data, rationale }).
//
// Trust model: this sidecar is untrusted. The Lean daemon never signs based
// on these drafts directly — every candidate is replayed through decode +
// simulate + user-confirm, and the user inspects simulated effects before
// signing. So an adversarial model (or prompt-injected context) can produce
// nonsense calldata and the worst that happens is the user sees a
// confusing simulation and bails.
//
// Phase 0 (this file): rule-based pattern matcher. Recognizes a few
// canonical English forms ("send 0.01 ETH to 0x…", "approve <token> for
// <spender>") and emits exact calldata. No model call yet — but the
// JSON-RPC surface is what matters; swapping in a real backend is a
// tools-and-prompt change, not an architectural one.
//
// Phase 1 (TODO): wrap the rule-based matcher as one tool the model can
// call, alongside `chain.balanceOf`, `registry.tokenAddress`,
// `protocol.uniswapQuote`. The model produces drafts; this file becomes
// the tool-router. Daemon mediates every tool call (policy + cache).
import {
  encodeFunctionData,
  parseAbiItem,
  isAddress,
  getAddress,
  parseUnits,
} from "viem";
import { KNOWN_TOKENS, KNOWN_PROTOCOLS } from "./known-tokens.mjs";
import { runAnthropicAgent } from "./anthropic-agent.mjs";

const erc20TransferAbi = parseAbiItem(
  "function transfer(address to, uint256 value)",
);
const erc20ApproveAbi = parseAbiItem(
  "function approve(address spender, uint256 value)",
);
// Aave V3 Pool — supply/withdraw use the same shape across chains.
const aaveSupplyAbi = parseAbiItem(
  "function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode)",
);
const aaveWithdrawAbi = parseAbiItem(
  "function withdraw(address asset, uint256 amount, address to)",
);

/** Sync rule-based pass. Returns null when nothing matched (so the async
 *  caller can fall through to the model agent); otherwise returns the
 *  candidates array. Pulled out so `draftFromIntent` stays readable. */
function ruleBasedDraft({ prompt, chainId, fromAddr }) {
  if (typeof prompt !== "string" || prompt.trim().length === 0) {
    return { candidates: [], reason: "prompt is empty" };
  }
  const norm = prompt.trim().toLowerCase();
  const candidates = [];

  // Pattern 1: "send <amount> ETH to <addr>"
  {
    const m = /\b(?:send|transfer)\s+([\d.]+)\s*eth\s+to\s+(0x[0-9a-fA-F]{40})\b/.exec(norm);
    if (m) {
      const amountEth = m[1];
      const to = getAddress(m[2]);
      const valueWei = parseUnits(amountEth, 18);
      candidates.push({
        to,
        value: "0x" + valueWei.toString(16),
        data: "0x",
        rationale: `Native ETH transfer of ${amountEth} ETH to ${to}.`,
        confidence: "high",
      });
    }
  }

  // Pattern 2: "send <amount> <SYMBOL> to <addr>" — non-ETH tokens only
  {
    const m = /\b(?:send|transfer)\s+([\d.]+)\s+([a-z]{2,10})\s+to\s+(0x[0-9a-fA-F]{40})\b/.exec(norm);
    if (m && m[2].toLowerCase() !== "eth") {
      const amount = m[1];
      const symbol = m[2].toUpperCase();
      const to = getAddress(m[3]);
      const tokenInfo = KNOWN_TOKENS[chainId]?.[symbol];
      if (tokenInfo) {
        const value = parseUnits(amount, tokenInfo.decimals);
        const data = encodeFunctionData({
          abi: [erc20TransferAbi],
          functionName: "transfer",
          args: [to, value],
        });
        candidates.push({
          to: tokenInfo.address,
          value: "0x0",
          data,
          rationale: `ERC-20 transfer: send ${amount} ${symbol} to ${to}. Token resolved from known-tokens dict (chainId ${chainId}, decimals ${tokenInfo.decimals}).`,
          confidence: "medium",
        });
      } else {
        candidates.push({
          rationale: `Recognized "send <amount> ${symbol} to <addr>" but ${symbol} is not in the known-tokens dict for chain ${chainId}. Pass the contract address explicitly.`,
          confidence: "rejected",
        });
      }
    }
  }

  // Pattern 3: "approve <SYMBOL> for <addr>" (unlimited; rare but flagged
  // explicitly so the user sees the warning at confirm time).
  {
    const m = /\bapprove\s+([a-z]{2,10})\s+for\s+(0x[0-9a-fA-F]{40})\b/.exec(norm);
    if (m) {
      const symbol = m[1].toUpperCase();
      const spender = getAddress(m[2]);
      const tokenInfo = KNOWN_TOKENS[chainId]?.[symbol];
      if (tokenInfo) {
        const data = encodeFunctionData({
          abi: [erc20ApproveAbi],
          functionName: "approve",
          args: [spender, (1n << 256n) - 1n],
        });
        candidates.push({
          to: tokenInfo.address,
          value: "0x0",
          data,
          rationale: `UNLIMITED ERC-20 approval: ${symbol} → ${spender}. Confirm step will flag this as HIGH RISK.`,
          confidence: "low",
          warning: "unlimited approval — review carefully",
        });
      }
    }
  }

  // Pattern 4: "supply <amount> <SYMBOL> to aave"
  // Aave's `supply` requires the supplied asset to be approved for the
  // Pool first. We emit BOTH calls as candidates — the user picks the
  // approve first (or skips if already approved).
  {
    const m = /\bsupply\s+([\d.]+)\s+([a-z]{2,10})\s+(?:to|on)\s+aave\b/.exec(norm);
    if (m && fromAddr) {
      const amount = m[1];
      const symbol = m[2].toUpperCase();
      const tokenInfo = KNOWN_TOKENS[chainId]?.[symbol];
      const pool = KNOWN_PROTOCOLS[chainId]?.aaveV3Pool;
      if (tokenInfo && pool) {
        const value = parseUnits(amount, tokenInfo.decimals);
        const beneficiary = getAddress(fromAddr);
        // Step 1: approve the Pool to pull `value` from us.
        candidates.push({
          to: tokenInfo.address,
          value: "0x0",
          data: encodeFunctionData({
            abi: [erc20ApproveAbi],
            functionName: "approve",
            args: [pool, value],
          }),
          rationale: `(1/2) Approve Aave V3 Pool to pull ${amount} ${symbol}. Signing this lets the next call move tokens.`,
          confidence: "high",
          step: 1,
          ofSteps: 2,
        });
        // Step 2: supply to Aave V3 on behalf of fromAddr.
        candidates.push({
          to: pool,
          value: "0x0",
          data: encodeFunctionData({
            abi: [aaveSupplyAbi],
            functionName: "supply",
            args: [tokenInfo.address, value, beneficiary, 0],
          }),
          rationale: `(2/2) Supply ${amount} ${symbol} to Aave V3 Pool on behalf of ${beneficiary} (referral code 0).`,
          confidence: "medium",
          step: 2,
          ofSteps: 2,
        });
      } else if (!fromAddr) {
        candidates.push({
          rationale: "Aave supply needs the sender's address (fromAddr in the request) — pass it so the daemon knows whose position to credit.",
          confidence: "rejected",
        });
      } else {
        candidates.push({
          rationale: `Recognized Aave supply intent but ${symbol} isn't in the known-tokens dict for chain ${chainId}, or Aave isn't deployed there.`,
          confidence: "rejected",
        });
      }
    }
  }

  // Pattern 5: "withdraw <amount> <SYMBOL> from aave"
  {
    const m = /\bwithdraw\s+([\d.]+)\s+([a-z]{2,10})\s+from\s+aave\b/.exec(norm);
    if (m && fromAddr) {
      const amount = m[1];
      const symbol = m[2].toUpperCase();
      const tokenInfo = KNOWN_TOKENS[chainId]?.[symbol];
      const pool = KNOWN_PROTOCOLS[chainId]?.aaveV3Pool;
      if (tokenInfo && pool) {
        const value = parseUnits(amount, tokenInfo.decimals);
        const recipient = getAddress(fromAddr);
        candidates.push({
          to: pool,
          value: "0x0",
          data: encodeFunctionData({
            abi: [aaveWithdrawAbi],
            functionName: "withdraw",
            args: [tokenInfo.address, value, recipient],
          }),
          rationale: `Withdraw ${amount} ${symbol} from Aave V3 Pool, send to ${recipient}.`,
          confidence: "high",
        });
      }
    }
  }

  if (candidates.length === 0) return null;
  return { candidates, fromAddr: fromAddr ?? null, chainId, source: "rules" };
}

/** Async draft pipeline: try rules first (fast, free, deterministic).
 *  Fall through to the Anthropic agent when rules miss AND the API key is
 *  configured. The wire shape is identical so callers don't have to know
 *  which path produced the candidates. */
export async function draftFromIntent({ prompt, chainId, fromAddr }) {
  if (typeof prompt !== "string" || prompt.trim().length === 0) {
    return { candidates: [], reason: "prompt is empty" };
  }

  const ruleHit = ruleBasedDraft({ prompt, chainId, fromAddr });
  if (ruleHit) return ruleHit;

  // Rules missed. If we have an API key, ask the model.
  if (process.env.ANTHROPIC_API_KEY) {
    const agentResult = await runAnthropicAgent({ prompt, chainId, fromAddr });
    if (agentResult.candidates && agentResult.candidates.length > 0) {
      return { ...agentResult, source: "anthropic" };
    }
    return {
      candidates: [],
      reason:
        agentResult.reason ??
        "model returned no candidates. The rule-based fallback also missed; refine the prompt or supply addresses explicitly.",
      source: "anthropic",
    };
  }

  return {
    candidates: [],
    reason:
      'no rule matched the prompt and ANTHROPIC_API_KEY is not set. Rule-based v0 supports: "send <amount> ETH to <addr>", "send <amount> <SYMBOL> to <addr>", "approve <SYMBOL> for <spender>", "supply <amount> <SYMBOL> to aave", "withdraw <amount> <SYMBOL> from aave". Set ANTHROPIC_API_KEY to enable model fallback.',
    source: "rules",
  };
}

export function validateDraft(d) {
  if (!d) return false;
  if (typeof d.to !== "string" || !isAddress(d.to)) return false;
  if (typeof d.value !== "string" || !d.value.startsWith("0x")) return false;
  if (typeof d.data !== "string" || !d.data.startsWith("0x")) return false;
  return true;
}
