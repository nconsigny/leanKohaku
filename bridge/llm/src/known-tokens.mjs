// Tiny well-known-token registry. The LLM is allowed to resolve symbols
// like "USDC" → address through this dict; anything else MUST be supplied
// by the user (or fetched via tools that the daemon mediates). This avoids
// the LLM hallucinating contract addresses.
//
// Phase 2.x: replace with a daemon-mediated lookup so the LLM has to ask
// the daemon ("what's the address for USDC on chain N?") and the daemon
// can refuse if the symbol is ambiguous or the chain is unsupported.
// Per-chain protocol contract addresses that the rule-based matcher can
// resolve from English ("Aave on mainnet"). Same hallucination concern as
// KNOWN_TOKENS: anything not in this dict has to be supplied by the user.
export const KNOWN_PROTOCOLS = {
  1: {
    aaveV3Pool:        "0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2",
    morphoBlue:        "0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb",
    uniswapV3QuoterV2: "0x61fFE014bA17989E743c5F6cB21bF9697530B21e",
    uniswapV3Router02: "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45",
  },
  11155111: {
    aaveV3Pool:        "0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951",
    uniswapV3QuoterV2: "0xEd1f6473345F45b75F8179591dd5bA1888cf2FB3",
    uniswapV3Router02: "0x3bFA4769FB09eefC5a80d6E87c3B9C650f7Ae48E",
  },
};

export const KNOWN_TOKENS = {
  1: {
    USDC: { address: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", decimals: 6  },
    USDT: { address: "0xdAC17F958D2ee523a2206206994597C13D831ec7", decimals: 6  },
    DAI:  { address: "0x6B175474E89094C44Da98b954EedeAC495271d0F", decimals: 18 },
    WETH: { address: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", decimals: 18 },
    WBTC: { address: "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599", decimals: 8  },
  },
  11155111: {
    WETH: { address: "0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14", decimals: 18 },
    USDC: { address: "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238", decimals: 6  },
  },
};
