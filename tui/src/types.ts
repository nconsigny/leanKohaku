/**
 * TS mirrors of the daemon's JSON-RPC response shapes that the TUI consumes.
 * Keep these handwritten and minimal — only the fields the TUI actually
 * reads. The daemon is the source of truth; if a field is missing here it
 * just isn't displayed.
 */

export type SlotKind = "eoa" | "tpm";

export type EoaListEntry = {
  name: string;
  address: string;
  unlocked?: boolean;
  derivationPath?: string;
};

export type TpmListEntry = {
  name: string;
  address: string;
};

export type ChainBalance = {
  /** Hex-encoded wei, e.g. "0x16345785d8a0000". */
  balance: string;
};

export type Wallet = {
  kind: SlotKind;
  name: string;
  address: string;
  /** wei as bigint, undefined while loading. */
  balanceWei?: bigint;
  /** present for EOAs; absent for TPM. */
  unlocked?: boolean;
};
