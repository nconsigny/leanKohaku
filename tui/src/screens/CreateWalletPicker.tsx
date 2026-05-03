import React from "react";
import { useInput } from "ink";
import SelectInput from "ink-select-input";
import { Layout } from "../widgets/Layout.js";

export type CreateKind = "eoa" | "r1" | "back";

type Props = {
  onPick: (k: CreateKind) => void;
};

/** Step 1 of the create-wallet flow: pick the slot type. The actual key
 *  generation lives in CreateEoaFlow / CreateR1Flow. */
export default function CreateWalletPicker({ onPick }: Props) {
  useInput((input, key) => {
    if (key.escape || input === "q") onPick("back");
  });

  const items: { label: string; value: CreateKind }[] = [
    { label: "EOA — BIP-39 mnemonic, passphrase-encrypted at rest", value: "eoa" },
    { label: "TPM/R1 — hardware-backed P-256 key, biometric prompts", value: "r1" },
    { label: "← Back",                                               value: "back" },
  ];

  return (
    <Layout
      title="Create wallet"
      subtitle="Choose the key type. EOA keys are software; TPM/R1 keys live in your TPM."
      hint="↑/↓ move · enter select · esc back"
    >
      <SelectInput items={items} onSelect={(it) => onPick(it.value)} />
    </Layout>
  );
}
