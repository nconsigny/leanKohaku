// Anthropic-backed agent loop for tx.draftFromIntent.
//
// Trust model (load-bearing): the model is untrusted. It can produce wrong
// or adversarial calldata; that's why every emitted candidate flows through
// the daemon's decode → simulate → user-confirm gate. The agent's job is
// only to *propose* — it never signs.
//
// To keep the model from hand-encoding wrong bytes, the tools it can call
// emit pre-encoded calldata via viem. The model picks recipes; viem builds
// the bytes. The model can also fall through to `emit_raw_calldata` when
// none of the recipes fit — that's strictly more dangerous, but the user
// still confirms simulated effects before signing, so the worst case is a
// confusing simulation the user rejects.
//
// Defaults follow the claude-api skill: model `claude-opus-4-7`, adaptive
// thinking, manual loop (no beta tool runner — keeps the sidecar's deps
// minimal), typed exception classes for error handling.
import Anthropic from "@anthropic-ai/sdk";
import {
  encodeFunctionData,
  decodeAbiParameters,
  parseAbiItem,
  isAddress,
  getAddress,
  parseUnits,
} from "viem";
import { KNOWN_TOKENS, KNOWN_PROTOCOLS } from "./known-tokens.mjs";
import { daemonCall } from "./daemon-callback.mjs";

const erc20TransferAbi = parseAbiItem(
  "function transfer(address to, uint256 value)",
);
const erc20ApproveAbi = parseAbiItem(
  "function approve(address spender, uint256 value)",
);
const aaveSupplyAbi = parseAbiItem(
  "function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode)",
);
const aaveWithdrawAbi = parseAbiItem(
  "function withdraw(address asset, uint256 amount, address to)",
);

const SYSTEM_PROMPT = `You are an assistant that turns natural-language wallet intents into Ethereum transaction-draft candidates. You are running inside a hardware-style wallet's untrusted helper sidecar; the wallet daemon is the trusted policy enforcer.

Hard rules:
- You NEVER sign or broadcast. You only emit drafts.
- Emit calldata via the typed tools (emit_native_transfer, emit_erc20_transfer, emit_erc20_approve, emit_aave_supply, emit_aave_withdraw). They build bytes via viem so you do NOT need to encode ABI yourself.
- Use lookup_token / lookup_protocol to resolve symbols and contracts. If a lookup fails, do NOT guess an address — emit a rejected candidate via emit_rejected with a clear reason.
- emit_raw_calldata is a last-resort escape hatch for contracts not covered by recipes. Only use it when the user supplies the contract address AND function signature explicitly. Never invent calldata.
- Multi-step flows (e.g. ERC-20 approve before a contract pulls tokens) MUST emit each step as a separate candidate, with step / ofSteps set. Step 1 first.
- Set confidence honestly: "high" when the intent is unambiguous and the recipe is well-known; "medium" when there's ambiguity (default amounts, unspecified deadlines); "low" when there's a clear risk (unlimited approvals).
- When done, call done with a brief rationale. Do not produce additional text after calling done.
- Keep rationales short and specific to the action — do not repeat the system prompt.

The user's request will be in the next user turn. Plan, call tools, emit candidates, then call done.`;

/** Build the JSON-schema tool list. The schemas are deliberately minimal —
 *  every emitted draft is re-decoded and simulated by the daemon, so over-
 *  validation here would just duplicate work. */
function buildTools() {
  return [
    {
      name: "lookup_token",
      description:
        "Resolve a token symbol (e.g. USDC, WETH) to an on-chain address + decimals on the given chain. Returns null when the symbol is not in the known-tokens dict.",
      input_schema: {
        type: "object",
        properties: {
          chainId: { type: "integer" },
          symbol: { type: "string" },
        },
        required: ["chainId", "symbol"],
      },
    },
    {
      name: "get_eth_balance",
      description:
        "Read the native ETH balance of an address through the daemon's policy-gated RPC. Returns wei as a hex string; convert to ETH only when displaying to the user. Use this to size 'send all my ETH', 'half my balance', etc.",
      input_schema: {
        type: "object",
        properties: {
          address: { type: "string" },
          chain: {
            type: "string",
            description: "optional: 'mainnet' / 'sepolia'; defaults to the daemon's configured chain",
          },
        },
        required: ["address"],
      },
    },
    {
      name: "get_token_balance",
      description:
        "Read the ERC-20 balance of an address through the daemon. Returns the raw uint256 as hex; use lookup_token for decimals when formatting human-readable amounts.",
      input_schema: {
        type: "object",
        properties: {
          token: { type: "string" },
          owner: { type: "string" },
          chain: { type: "string" },
        },
        required: ["token", "owner"],
      },
    },
    {
      name: "get_gas_price",
      description:
        "Read current gas price from the chain through the daemon. Returns wei as hex. Use this only when the user asks about cost or to size gas-aware operations; you don't need to call this for every transaction.",
      input_schema: {
        type: "object",
        properties: {
          chain: { type: "string" },
        },
      },
    },
    {
      name: "get_uniswap_v3_quote",
      description:
        "Quote a Uniswap V3 single-hop swap via QuoterV2.quoteExactInputSingle. Returns amountOut and the quoter's gas estimate. Use this to compare slippage and pool fees before drafting a swap. The fee tier (in hundredths of a bip — 500 = 0.05%, 3000 = 0.3%, 10000 = 1%) is the pool selector; try common tiers if you're not sure. amountIn is the raw uint256 of the input token (use lookup_token for decimals).",
      input_schema: {
        type: "object",
        properties: {
          chainId: { type: "integer" },
          tokenIn: { type: "string" },
          tokenOut: { type: "string" },
          amountIn: { type: "string", description: "human-readable amount of tokenIn, e.g. '1.5'" },
          decimalsIn: { type: "integer" },
          fee: { type: "integer", description: "pool fee tier: 100, 500, 3000, or 10000" },
          chain: { type: "string" },
        },
        required: ["chainId", "tokenIn", "tokenOut", "amountIn", "decimalsIn", "fee"],
      },
    },
    {
      name: "get_uniswap_v3_multi_hop_quote",
      description:
        "Quote a Uniswap V3 multi-hop swap (e.g. USDC → WETH → DAI when no direct USDC/DAI pool exists). `tokens` is the path in order (≥2 addresses); `fees` is the per-hop fee tier (length = tokens.length - 1). Returns amountOut and the per-hop sqrtPrice + ticks-crossed arrays. Use this when get_uniswap_v3_quote (single-hop) returns no pool, or when the user explicitly asks for a multi-hop route.",
      input_schema: {
        type: "object",
        properties: {
          chainId: { type: "integer" },
          tokens: {
            type: "array",
            items: { type: "string" },
            description: "ordered list of token addresses, length ≥ 2",
          },
          fees: {
            type: "array",
            items: { type: "integer" },
            description: "per-hop fee tier (100/500/3000/10000), length = tokens.length - 1",
          },
          amountIn: { type: "string", description: "human-readable amount of tokens[0]" },
          decimalsIn: { type: "integer" },
          chain: { type: "string" },
        },
        required: ["chainId", "tokens", "fees", "amountIn", "decimalsIn"],
      },
    },
    {
      name: "get_morpho_blue_position",
      description:
        "Read a user's Morpho Blue position for a given market. Returns supplyShares, borrowShares, collateral, plus the market's accumulators (totalSupplyAssets/Shares, totalBorrowAssets/Shares, lastUpdate, fee) so you can compute supplyAssets and borrowAssets via the virtual-shares formula. The market is identified by its 32-byte `id` (keccak256 of the market params). For convenience, the tool also returns supplyAssets and borrowAssets pre-computed using toAssetsDown.",
      input_schema: {
        type: "object",
        properties: {
          chainId: { type: "integer" },
          marketId: { type: "string", description: "0x-prefixed 32-byte market id" },
          user: { type: "string" },
          chain: { type: "string" },
        },
        required: ["chainId", "marketId", "user"],
      },
    },
    {
      name: "get_aave_health_factor",
      description:
        "Read the user's Aave V3 account state via Pool.getUserAccountData(address). Returns totalCollateralBase, totalDebtBase, healthFactor (1e18 scale, < 1e18 = liquidatable), and ltv. Use this to size a borrow/withdraw without putting the user near liquidation. The Pool address is resolved via lookup_protocol(name='aaveV3Pool', chainId).",
      input_schema: {
        type: "object",
        properties: {
          chainId: { type: "integer" },
          user: { type: "string", description: "the user's address — usually fromAddr" },
          chain: { type: "string", description: "optional chain hint, e.g. 'mainnet'" },
        },
        required: ["chainId", "user"],
      },
    },
    {
      name: "lookup_protocol",
      description:
        "Resolve a protocol name (e.g. aaveV3Pool, morphoBlue) to its contract address on the given chain. Returns null when the protocol is not deployed there per the known-protocols dict.",
      input_schema: {
        type: "object",
        properties: {
          chainId: { type: "integer" },
          name: { type: "string" },
        },
        required: ["chainId", "name"],
      },
    },
    {
      name: "emit_native_transfer",
      description:
        "Emit a native ETH transfer candidate. value is parsed as a decimal ETH string (e.g. '0.05').",
      input_schema: {
        type: "object",
        properties: {
          to: { type: "string", description: "0x… recipient address" },
          amountEth: { type: "string", description: "decimal ETH, e.g. '0.05'" },
          rationale: { type: "string" },
          confidence: { type: "string", enum: ["high", "medium", "low"] },
        },
        required: ["to", "amountEth", "rationale", "confidence"],
      },
    },
    {
      name: "emit_erc20_transfer",
      description:
        "Emit an ERC-20 transfer candidate. Use lookup_token first to get the token address + decimals.",
      input_schema: {
        type: "object",
        properties: {
          tokenAddress: { type: "string" },
          decimals: { type: "integer" },
          recipient: { type: "string" },
          amount: { type: "string", description: "human-readable amount, e.g. '100' or '0.5'" },
          rationale: { type: "string" },
          confidence: { type: "string", enum: ["high", "medium", "low"] },
        },
        required: ["tokenAddress", "decimals", "recipient", "amount", "rationale", "confidence"],
      },
    },
    {
      name: "emit_erc20_approve",
      description:
        "Emit an ERC-20 approve candidate. Mark confidence='low' for unlimited approvals (warn the user via rationale).",
      input_schema: {
        type: "object",
        properties: {
          tokenAddress: { type: "string" },
          decimals: { type: "integer" },
          spender: { type: "string" },
          amount: {
            type: "string",
            description:
              "human-readable amount, or 'max' for unlimited (2^256 - 1)",
          },
          rationale: { type: "string" },
          confidence: { type: "string", enum: ["high", "medium", "low"] },
        },
        required: ["tokenAddress", "decimals", "spender", "amount", "rationale", "confidence"],
      },
    },
    {
      name: "emit_aave_supply",
      description:
        "Emit BOTH the approve and supply candidates for Aave V3. The user will be presented with each step separately.",
      input_schema: {
        type: "object",
        properties: {
          chainId: { type: "integer" },
          tokenAddress: { type: "string" },
          decimals: { type: "integer" },
          amount: { type: "string" },
          onBehalfOf: { type: "string", description: "usually the sender's address" },
          rationale: { type: "string" },
        },
        required: ["chainId", "tokenAddress", "decimals", "amount", "onBehalfOf", "rationale"],
      },
    },
    {
      name: "emit_aave_withdraw",
      description: "Emit a single Aave V3 withdraw candidate.",
      input_schema: {
        type: "object",
        properties: {
          chainId: { type: "integer" },
          tokenAddress: { type: "string" },
          decimals: { type: "integer" },
          amount: { type: "string" },
          recipient: { type: "string" },
          rationale: { type: "string" },
        },
        required: ["chainId", "tokenAddress", "decimals", "amount", "recipient", "rationale"],
      },
    },
    {
      name: "emit_raw_calldata",
      description:
        "Last-resort: emit calldata the user supplied directly (or that you encoded yourself for a non-recipe contract). Set confidence='low' and explain exactly why this isn't covered by a recipe.",
      input_schema: {
        type: "object",
        properties: {
          to: { type: "string" },
          value: { type: "string", description: "hex-encoded wei, e.g. '0x0'" },
          data: { type: "string", description: "hex calldata, must start with 0x" },
          rationale: { type: "string" },
          confidence: { type: "string", enum: ["high", "medium", "low"] },
        },
        required: ["to", "value", "data", "rationale", "confidence"],
      },
    },
    {
      name: "emit_rejected",
      description:
        "Record that you understood the intent but cannot safely produce a draft (missing info, ambiguous, unsupported on this chain). The user will see the reason; nothing gets signed.",
      input_schema: {
        type: "object",
        properties: { reason: { type: "string" } },
        required: ["reason"],
      },
    },
    {
      name: "done",
      description: "Finish — no more drafts. Provide a one-sentence rationale summarizing what you produced.",
      input_schema: {
        type: "object",
        properties: { summary: { type: "string" } },
        required: ["summary"],
      },
    },
  ];
}

async function executeToolCall(name, input, ctx) {
  switch (name) {
    case "lookup_token": {
      const t = KNOWN_TOKENS[input.chainId]?.[input.symbol?.toUpperCase()];
      return t ? { address: t.address, decimals: t.decimals } : null;
    }
    case "lookup_protocol": {
      const addr = KNOWN_PROTOCOLS[input.chainId]?.[input.name];
      return addr ? { address: addr } : null;
    }
    case "get_eth_balance": {
      // Routes through the daemon (chain.balance) so the policy gate runs.
      const params = { address: input.address };
      if (input.chain) params.chain = input.chain;
      const r = await daemonCall("chain.balance", params);
      if (!r.ok) return { ok: false, error: r.error.message };
      return { balanceWei: r.result?.balance ?? "0x0" };
    }
    case "get_token_balance": {
      const params = { token: input.token, owner: input.owner };
      if (input.chain) params.chain = input.chain;
      const r = await daemonCall("chain.tokenBalance", params);
      if (!r.ok) return { ok: false, error: r.error.message };
      return { balance: r.result?.balance ?? "0x0" };
    }
    case "get_gas_price": {
      const params = {};
      if (input.chain) params.chain = input.chain;
      const r = await daemonCall("chain.gasPrice", params);
      if (!r.ok) return { ok: false, error: r.error.message };
      return { gasPriceWei: r.result?.gasPrice ?? "0x0" };
    }
    case "get_uniswap_v3_quote": {
      const quoter = KNOWN_PROTOCOLS[input.chainId]?.uniswapV3QuoterV2;
      if (!quoter) {
        return { ok: false, error: `Uniswap V3 QuoterV2 not configured for chainId ${input.chainId}` };
      }
      let amountIn;
      try {
        amountIn = parseUnits(input.amountIn, input.decimalsIn);
      } catch (e) {
        return { ok: false, error: `bad amountIn: ${e?.message ?? e}` };
      }
      // QuoterV2.quoteExactInputSingle((address,address,uint256,uint24,uint160))
      // → (uint256 amountOut, uint160 sqrtPriceX96After, uint32 ticksCrossed, uint256 gasEstimate)
      const item = parseAbiItem(
        "function quoteExactInputSingle((address tokenIn,address tokenOut,uint256 amountIn,uint24 fee,uint160 sqrtPriceLimitX96)) returns (uint256 amountOut, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate)",
      );
      const data = encodeFunctionData({
        abi: [item],
        functionName: "quoteExactInputSingle",
        args: [
          {
            tokenIn: getAddress(input.tokenIn),
            tokenOut: getAddress(input.tokenOut),
            amountIn,
            fee: input.fee,
            sqrtPriceLimitX96: 0n,
          },
        ],
      });
      const callParams = { to: quoter, data };
      if (input.chain) callParams.chain = input.chain;
      const r = await daemonCall("chain.ethCall", callParams);
      if (!r.ok) {
        // QuoterV2 reverts if no pool exists for the (tokenIn, tokenOut, fee)
        // triple — surface that as a useful tool result so the model can try
        // a different fee tier without giving up.
        return {
          ok: false,
          error: r.error.message,
          hint: "try a different fee tier (100, 500, 3000, or 10000) or check token addresses",
        };
      }
      const raw = r.result?.returnData;
      if (typeof raw !== "string") {
        return { ok: false, error: "no returnData from chain.ethCall" };
      }
      try {
        const decoded = decodeAbiParameters(
          [
            { name: "amountOut",                 type: "uint256" },
            { name: "sqrtPriceX96After",         type: "uint160" },
            { name: "initializedTicksCrossed",   type: "uint32"  },
            { name: "gasEstimate",               type: "uint256" },
          ],
          raw,
        );
        return {
          amountOut: decoded[0].toString(),
          sqrtPriceX96After: decoded[1].toString(),
          initializedTicksCrossed: Number(decoded[2]),
          gasEstimate: decoded[3].toString(),
          fee: input.fee,
          quoter,
        };
      } catch (e) {
        return { ok: false, error: `decode failed: ${e?.message ?? e}` };
      }
    }
    case "get_uniswap_v3_multi_hop_quote": {
      const quoter = KNOWN_PROTOCOLS[input.chainId]?.uniswapV3QuoterV2;
      if (!quoter) {
        return { ok: false, error: `Uniswap V3 QuoterV2 not configured for chainId ${input.chainId}` };
      }
      const tokens = Array.isArray(input.tokens) ? input.tokens : [];
      const fees = Array.isArray(input.fees) ? input.fees : [];
      if (tokens.length < 2) return { ok: false, error: "tokens must have ≥ 2 entries" };
      if (fees.length !== tokens.length - 1) {
        return { ok: false, error: `fees.length (${fees.length}) must be tokens.length - 1 (${tokens.length - 1})` };
      }
      let amountIn;
      try {
        amountIn = parseUnits(input.amountIn, input.decimalsIn);
      } catch (e) {
        return { ok: false, error: `bad amountIn: ${e?.message ?? e}` };
      }
      // V3 path encoding: tokenA(20) || feeAB(3) || tokenB(20) || feeBC(3) || tokenC(20)...
      // No viem helper for this — packed concatenation.
      let path = "0x";
      try {
        for (let i = 0; i < tokens.length; i++) {
          const t = getAddress(tokens[i]);
          path += t.slice(2);
          if (i < tokens.length - 1) {
            const fee = Number(fees[i]);
            if (!Number.isInteger(fee) || fee < 0 || fee > 0xffffff) {
              return { ok: false, error: `bad fee at hop ${i}: ${fees[i]}` };
            }
            path += fee.toString(16).padStart(6, "0");
          }
        }
      } catch (e) {
        return { ok: false, error: `path encoding failed: ${e?.message ?? e}` };
      }
      const item = parseAbiItem(
        "function quoteExactInput(bytes path, uint256 amountIn) returns (uint256 amountOut, uint160[] sqrtPriceX96AfterList, uint32[] initializedTicksCrossedList, uint256 gasEstimate)",
      );
      const data = encodeFunctionData({
        abi: [item],
        functionName: "quoteExactInput",
        args: [path, amountIn],
      });
      const callParams = { to: quoter, data };
      if (input.chain) callParams.chain = input.chain;
      const r = await daemonCall("chain.ethCall", callParams);
      if (!r.ok) {
        return {
          ok: false,
          error: r.error.message,
          hint: "QuoterV2 reverts when any hop has no pool at the chosen fee — try different fee tiers, or split into single-hop quotes to find which hop is missing",
        };
      }
      const raw = r.result?.returnData;
      if (typeof raw !== "string") {
        return { ok: false, error: "no returnData from chain.ethCall" };
      }
      try {
        const decoded = decodeAbiParameters(
          [
            { name: "amountOut",                  type: "uint256"   },
            { name: "sqrtPriceX96AfterList",      type: "uint160[]" },
            { name: "initializedTicksCrossedList",type: "uint32[]"  },
            { name: "gasEstimate",                type: "uint256"   },
          ],
          raw,
        );
        return {
          amountOut: decoded[0].toString(),
          sqrtPriceX96AfterList: Array.from(decoded[1]).map((x) => x.toString()),
          initializedTicksCrossedList: Array.from(decoded[2]).map((n) => Number(n)),
          gasEstimate: decoded[3].toString(),
          hops: tokens.length - 1,
          path,
          quoter,
        };
      } catch (e) {
        return { ok: false, error: `decode failed: ${e?.message ?? e}` };
      }
    }
    case "get_morpho_blue_position": {
      const morpho = KNOWN_PROTOCOLS[input.chainId]?.morphoBlue;
      if (!morpho) {
        return { ok: false, error: `Morpho Blue not configured for chainId ${input.chainId}` };
      }
      if (!/^0x[0-9a-fA-F]{64}$/.test(input.marketId ?? "")) {
        return { ok: false, error: "marketId must be a 0x-prefixed 32-byte hex" };
      }
      const positionAbi = parseAbiItem(
        "function position(bytes32 id, address user) view returns (uint256 supplyShares, uint128 borrowShares, uint128 collateral)",
      );
      const marketAbi = parseAbiItem(
        "function market(bytes32 id) view returns (uint128 totalSupplyAssets, uint128 totalSupplyShares, uint128 totalBorrowAssets, uint128 totalBorrowShares, uint128 lastUpdate, uint128 fee)",
      );
      const positionData = encodeFunctionData({
        abi: [positionAbi],
        functionName: "position",
        args: [input.marketId, getAddress(input.user)],
      });
      const marketData = encodeFunctionData({
        abi: [marketAbi],
        functionName: "market",
        args: [input.marketId],
      });
      const chainHint = input.chain ? { chain: input.chain } : {};
      // Two reads in parallel.
      const [posRes, mktRes] = await Promise.all([
        daemonCall("chain.ethCall", { to: morpho, data: positionData, ...chainHint }),
        daemonCall("chain.ethCall", { to: morpho, data: marketData, ...chainHint }),
      ]);
      if (!posRes.ok) return { ok: false, error: `position read: ${posRes.error.message}` };
      if (!mktRes.ok) return { ok: false, error: `market read: ${mktRes.error.message}` };
      try {
        const pos = decodeAbiParameters(
          [
            { name: "supplyShares", type: "uint256" },
            { name: "borrowShares", type: "uint128" },
            { name: "collateral",   type: "uint128" },
          ],
          posRes.result.returnData,
        );
        const mkt = decodeAbiParameters(
          [
            { name: "totalSupplyAssets", type: "uint128" },
            { name: "totalSupplyShares", type: "uint128" },
            { name: "totalBorrowAssets", type: "uint128" },
            { name: "totalBorrowShares", type: "uint128" },
            { name: "lastUpdate",        type: "uint128" },
            { name: "fee",               type: "uint128" },
          ],
          mktRes.result.returnData,
        );
        // Morpho's toAssetsDown: shares * (totalAssets + VIRTUAL_ASSETS) / (totalShares + VIRTUAL_SHARES)
        // VIRTUAL_ASSETS = 1, VIRTUAL_SHARES = 1e6.
        const VA = 1n;
        const VS = 1000000n;
        const supplyShares = pos[0];
        const borrowShares = BigInt(pos[1]);
        const collateral = BigInt(pos[2]);
        const totalSupplyAssets = BigInt(mkt[0]);
        const totalSupplyShares = BigInt(mkt[1]);
        const totalBorrowAssets = BigInt(mkt[2]);
        const totalBorrowShares = BigInt(mkt[3]);
        const supplyAssets =
          totalSupplyShares + VS === 0n
            ? 0n
            : (supplyShares * (totalSupplyAssets + VA)) / (totalSupplyShares + VS);
        const borrowAssets =
          totalBorrowShares + VS === 0n
            ? 0n
            : (borrowShares * (totalBorrowAssets + VA)) / (totalBorrowShares + VS);
        return {
          supplyShares: supplyShares.toString(),
          supplyAssets: supplyAssets.toString(),
          borrowShares: borrowShares.toString(),
          borrowAssets: borrowAssets.toString(),
          collateral: collateral.toString(),
          market: {
            totalSupplyAssets: totalSupplyAssets.toString(),
            totalSupplyShares: totalSupplyShares.toString(),
            totalBorrowAssets: totalBorrowAssets.toString(),
            totalBorrowShares: totalBorrowShares.toString(),
            lastUpdate: mkt[4].toString(),
            fee: mkt[5].toString(),
          },
          // Token decimals are NOT included — the tool doesn't know which
          // token is loan vs collateral. Use idToMarketParams or
          // lookup_token if you need to format human-readable amounts.
        };
      } catch (e) {
        return { ok: false, error: `decode failed: ${e?.message ?? e}` };
      }
    }
    case "get_aave_health_factor": {
      const pool = KNOWN_PROTOCOLS[input.chainId]?.aaveV3Pool;
      if (!pool) return { ok: false, error: `Aave V3 not configured for chainId ${input.chainId}` };
      // selector: getUserAccountData(address) = 0xbf92857c
      const item = parseAbiItem(
        "function getUserAccountData(address user) view returns (uint256 totalCollateralBase, uint256 totalDebtBase, uint256 availableBorrowsBase, uint256 currentLiquidationThreshold, uint256 ltv, uint256 healthFactor)",
      );
      const data = encodeFunctionData({
        abi: [item],
        functionName: "getUserAccountData",
        args: [getAddress(input.user)],
      });
      const callParams = { to: pool, data };
      if (input.chain) callParams.chain = input.chain;
      const r = await daemonCall("chain.ethCall", callParams);
      if (!r.ok) return { ok: false, error: r.error.message };
      const raw = r.result?.returnData;
      if (typeof raw !== "string") {
        return { ok: false, error: "no returnData from chain.ethCall" };
      }
      try {
        const decoded = decodeAbiParameters(
          [
            { name: "totalCollateralBase",          type: "uint256" },
            { name: "totalDebtBase",                type: "uint256" },
            { name: "availableBorrowsBase",         type: "uint256" },
            { name: "currentLiquidationThreshold",  type: "uint256" },
            { name: "ltv",                          type: "uint256" },
            { name: "healthFactor",                 type: "uint256" },
          ],
          raw,
        );
        return {
          totalCollateralBase: decoded[0].toString(),
          totalDebtBase: decoded[1].toString(),
          availableBorrowsBase: decoded[2].toString(),
          currentLiquidationThreshold: decoded[3].toString(),
          ltv: decoded[4].toString(),
          // Aave returns healthFactor scaled by 1e18; uint256 max means
          // "no debt" / infinite. Surface both raw and a friendly note.
          healthFactor: decoded[5].toString(),
          healthFactorNote:
            decoded[1] === 0n
              ? "user has no debt; healthFactor is the uint256 sentinel (effectively infinite)"
              : `healthFactor is scaled by 1e18; below 1e18 means liquidatable`,
        };
      } catch (e) {
        return { ok: false, error: `decode failed: ${e?.message ?? e}` };
      }
    }
    case "emit_native_transfer": {
      const valueWei = parseUnits(input.amountEth, 18);
      ctx.candidates.push({
        to: getAddress(input.to),
        value: "0x" + valueWei.toString(16),
        data: "0x",
        rationale: input.rationale,
        confidence: input.confidence,
      });
      return { ok: true };
    }
    case "emit_erc20_transfer": {
      const value = parseUnits(input.amount, input.decimals);
      ctx.candidates.push({
        to: getAddress(input.tokenAddress),
        value: "0x0",
        data: encodeFunctionData({
          abi: [erc20TransferAbi],
          functionName: "transfer",
          args: [getAddress(input.recipient), value],
        }),
        rationale: input.rationale,
        confidence: input.confidence,
      });
      return { ok: true };
    }
    case "emit_erc20_approve": {
      const value =
        input.amount === "max"
          ? (1n << 256n) - 1n
          : parseUnits(input.amount, input.decimals);
      ctx.candidates.push({
        to: getAddress(input.tokenAddress),
        value: "0x0",
        data: encodeFunctionData({
          abi: [erc20ApproveAbi],
          functionName: "approve",
          args: [getAddress(input.spender), value],
        }),
        rationale: input.rationale,
        confidence: input.confidence,
        ...(input.amount === "max"
          ? { warning: "unlimited approval" }
          : {}),
      });
      return { ok: true };
    }
    case "emit_aave_supply": {
      const pool = KNOWN_PROTOCOLS[input.chainId]?.aaveV3Pool;
      if (!pool) {
        return { ok: false, error: `Aave V3 not configured for chainId ${input.chainId}` };
      }
      const value = parseUnits(input.amount, input.decimals);
      const beneficiary = getAddress(input.onBehalfOf);
      const tokenAddr = getAddress(input.tokenAddress);
      ctx.candidates.push({
        to: tokenAddr,
        value: "0x0",
        data: encodeFunctionData({
          abi: [erc20ApproveAbi],
          functionName: "approve",
          args: [pool, value],
        }),
        rationale: `(1/2) Approve Aave V3 Pool to pull ${input.amount} of ${tokenAddr}. ${input.rationale}`,
        confidence: "high",
        step: 1,
        ofSteps: 2,
      });
      ctx.candidates.push({
        to: pool,
        value: "0x0",
        data: encodeFunctionData({
          abi: [aaveSupplyAbi],
          functionName: "supply",
          args: [tokenAddr, value, beneficiary, 0],
        }),
        rationale: `(2/2) Supply ${input.amount} of ${tokenAddr} on behalf of ${beneficiary}. ${input.rationale}`,
        confidence: "medium",
        step: 2,
        ofSteps: 2,
      });
      return { ok: true };
    }
    case "emit_aave_withdraw": {
      const pool = KNOWN_PROTOCOLS[input.chainId]?.aaveV3Pool;
      if (!pool) {
        return { ok: false, error: `Aave V3 not configured for chainId ${input.chainId}` };
      }
      const value = parseUnits(input.amount, input.decimals);
      ctx.candidates.push({
        to: pool,
        value: "0x0",
        data: encodeFunctionData({
          abi: [aaveWithdrawAbi],
          functionName: "withdraw",
          args: [getAddress(input.tokenAddress), value, getAddress(input.recipient)],
        }),
        rationale: input.rationale,
        confidence: "high",
      });
      return { ok: true };
    }
    case "emit_raw_calldata": {
      if (!isAddress(input.to)) return { ok: false, error: "invalid `to`" };
      if (!input.data?.startsWith("0x")) {
        return { ok: false, error: "`data` must be 0x-prefixed hex" };
      }
      ctx.candidates.push({
        to: getAddress(input.to),
        value: input.value,
        data: input.data,
        rationale: input.rationale,
        confidence: input.confidence,
      });
      return { ok: true };
    }
    case "emit_rejected": {
      ctx.candidates.push({
        rationale: input.reason,
        confidence: "rejected",
      });
      return { ok: true };
    }
    case "done":
      ctx.summary = input.summary;
      return { ok: true, done: true };
    default:
      return { ok: false, error: `unknown tool: ${name}` };
  }
}

/** Run the agent loop. Returns the same shape as the rule-based path:
 *  `{ candidates, fromAddr, chainId, rationale }`. Bounded by `maxIters` to
 *  prevent runaway tool-use loops on a confused model. */
export async function runAnthropicAgent({ prompt, chainId, fromAddr }, opts = {}) {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    return {
      candidates: [],
      reason:
        "ANTHROPIC_API_KEY not set; rule-based matcher missed and there's no model fallback configured.",
    };
  }

  const client = new Anthropic({ apiKey });
  const tools = buildTools();
  const ctx = { candidates: [], summary: null };

  const userMessage = `User prompt: ${JSON.stringify(prompt)}
chainId: ${chainId}
fromAddr (sender's address): ${fromAddr ?? "(not provided — ask via emit_rejected if needed)"}

Produce one or more transaction-draft candidates by calling the emit_* tools, then call done.`;

  const messages = [{ role: "user", content: userMessage }];
  const maxIters = opts.maxIters ?? 8;

  let response;
  for (let iter = 0; iter < maxIters; iter++) {
    try {
      response = await client.messages.create({
        model: "claude-opus-4-7",
        max_tokens: 16000,
        thinking: { type: "adaptive" },
        system: SYSTEM_PROMPT,
        tools,
        messages,
      });
    } catch (e) {
      // Typed exceptions per the SDK — surface a clean reason.
      if (e instanceof Anthropic.RateLimitError) {
        return { candidates: [], reason: "Anthropic rate limited; retry shortly." };
      }
      if (e instanceof Anthropic.APIError) {
        return {
          candidates: [],
          reason: `Anthropic API error ${e.status}: ${e.message}`,
        };
      }
      return { candidates: [], reason: `agent error: ${e?.message ?? e}` };
    }

    if (response.stop_reason === "end_turn") break;

    const toolUses = response.content.filter((b) => b.type === "tool_use");
    if (toolUses.length === 0) break;

    messages.push({ role: "assistant", content: response.content });

    const toolResults = [];
    let doneFlag = false;
    for (const t of toolUses) {
      let result;
      try {
        result = await executeToolCall(t.name, t.input, ctx);
      } catch (e) {
        result = { ok: false, error: `tool execution failed: ${e?.message ?? e}` };
      }
      if (result?.done) doneFlag = true;
      toolResults.push({
        type: "tool_result",
        tool_use_id: t.id,
        content: JSON.stringify(result),
        is_error: result?.ok === false,
      });
    }

    if (doneFlag) break;

    messages.push({ role: "user", content: toolResults });
  }

  return {
    candidates: ctx.candidates,
    fromAddr: fromAddr ?? null,
    chainId,
    rationale: ctx.summary ?? "agent finished without a summary",
  };
}
