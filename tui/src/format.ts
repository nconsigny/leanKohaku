/** Format a wei amount as ETH with up to 18 trimmed decimals. */
export function formatEth(wei: bigint): string {
  const negative = wei < 0n;
  const abs = negative ? -wei : wei;
  const whole = abs / 10n ** 18n;
  const frac = abs % 10n ** 18n;
  if (frac === 0n) return `${negative ? "-" : ""}${whole} ETH`;
  const fracStr = frac.toString().padStart(18, "0").replace(/0+$/, "");
  return `${negative ? "-" : ""}${whole}.${fracStr} ETH`;
}

/** Decode a `0x`-prefixed hex string to bigint. Returns 0n on bad input. */
export function hexToBigInt(hex: string | undefined | null): bigint {
  if (!hex) return 0n;
  const body = hex.startsWith("0x") || hex.startsWith("0X") ? hex.slice(2) : hex;
  if (body.length === 0) return 0n;
  try {
    return BigInt("0x" + body);
  } catch {
    return 0n;
  }
}

/** Address shorthand used in the wallet list — `0xAa65…C02C`. */
export function shortAddr(addr: string): string {
  if (!addr || addr.length < 12) return addr;
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}
