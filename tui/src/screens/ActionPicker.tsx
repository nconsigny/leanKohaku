import React from "react";
import { Box, Text, useInput } from "ink";
import SelectInput from "ink-select-input";
import { theme } from "../theme.js";
import { Wallet } from "../types.js";
import { formatEth, shortAddr } from "../format.js";

export type Action =
  | "send"
  | "shield"
  | "history"
  | "details"
  | "balance-refresh"
  | "lock-toggle"
  | "reveal-mnemonic"
  | "back";

type Props = {
  wallet: Wallet;
  onPick: (action: Action) => void;
  onBack: () => void;
};

export default function ActionPicker({ wallet, onPick, onBack }: Props) {
  useInput((input, key) => {
    if (key.escape || input === "q") onBack();
  });

  const items: { label: string; value: Action }[] = [
    { label: "Send ETH",                       value: "send" },
    ...(wallet.kind === "eoa"
      ? [{ label: "Shield (Privacy Pools deposit)", value: "shield" as Action }]
      : []),
    ...(wallet.kind === "eoa"
      ? [
          {
            label: wallet.unlocked
              ? "Lock wallet"
              : "Unlock wallet (passphrase)",
            value: "lock-toggle" as Action,
          },
        ]
      : []),
    { label: "View on-chain history",          value: "history" },
    { label: "Show wallet details",            value: "details" },
    { label: "Refresh balance",                value: "balance-refresh" },
    ...(wallet.kind === "eoa"
      ? [{ label: "Reveal mnemonic (DANGER)",   value: "reveal-mnemonic" as Action }]
      : []),
    { label: "← Back to wallet list",          value: "back" },
  ];

  return (
    <Box flexDirection="column" paddingX={1}>
      <Text color={theme.primary} bold>
        {wallet.name}{" "}
        <Text color={wallet.kind === "eoa" ? theme.primary : theme.ok}>
          [{wallet.kind}]
        </Text>
        {wallet.kind === "eoa" && wallet.unlocked === false && (
          <Text color={theme.warn}> [locked]</Text>
        )}
      </Text>
      <Text color={theme.dim}>
        {shortAddr(wallet.address)} ·{" "}
        {wallet.balanceWei !== undefined ? formatEth(wallet.balanceWei) : "…"}
      </Text>
      <Box marginTop={1}>
        <SelectInput
          items={items}
          onSelect={(it) => {
            if (it.value === "back") onBack();
            else onPick(it.value);
          }}
        />
      </Box>
      <Box marginTop={1}>
        <Text color={theme.dim}>↑/↓ move · enter select · esc back</Text>
      </Box>
    </Box>
  );
}
