import React from "react";
import { Box, Text, useInput } from "ink";
import SelectInput from "ink-select-input";
import { Layout } from "../widgets/Layout.js";
import KohakuKoi from "../widgets/KohakuKoi.js";
import { theme } from "../theme.js";

export type MainAction =
  | "wallets"
  | "create-wallet"
  | "import-wallet"
  | "privacy"
  | "daemon"
  | "more"
  | "quit";

type Props = {
  onPick: (a: MainAction) => void;
};

/** Top-level entry. The "Wallets" item is the most-used path; everything
 *  else is workflow-organized rather than namespace-organized so users
 *  don't need to know the CLI verb tree. */
export default function MainMenu({ onPick }: Props) {
  useInput((input) => {
    if (input === "q") onPick("quit");
  });

  const items: { label: string; value: MainAction }[] = [
    { label: "Wallets — list, send, shield, history",         value: "wallets" },
    { label: "Create wallet",                                 value: "create-wallet" },
    { label: "Import wallet",                                 value: "import-wallet" },
    { label: "Privacy Pools (balance / mnemonic / unshield)", value: "privacy" },
    { label: "Daemon status",                                 value: "daemon" },
    { label: "More commands (advanced)",                      value: "more" },
    { label: "Quit",                                          value: "quit" },
  ];

  return (
    <Layout
      title="leanKohaku — interactive wallet"
      subtitle="formally-verified Ethereum wallet · daemon: leankohaku-daemon"
      hint="↑/↓ move · enter select · q quit"
    >
      <Box flexDirection="row">
        <Box marginRight={2}>
          <KohakuKoi size="tiny" />
        </Box>
        <Box
          flexDirection="column"
          justifyContent="center"
          borderStyle="double"
          borderColor={theme.koiRed}
          paddingX={2}
          paddingY={0}
        >
          <Text color={theme.koiCream} backgroundColor={theme.koiInk} bold>
            {" leanKohaku · interactive wallet "}
          </Text>
          <Box marginTop={1}>
            <SelectInput items={items} onSelect={(it) => onPick(it.value)} />
          </Box>
        </Box>
      </Box>
    </Layout>
  );
}
