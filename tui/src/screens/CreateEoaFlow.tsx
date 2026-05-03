import React, { useState } from "react";
import { Box, Text } from "ink";
import { Layout } from "../widgets/Layout.js";
import Form, { Field } from "../widgets/Form.js";
import RpcRunner from "../widgets/RpcRunner.js";
import { theme } from "../theme.js";

type Props = { onDone: (success: boolean) => void };

const NAME_RE = /^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$/;
const PATH_RE = /^m(\/[0-9]+'?)+$/;

/** Inline wallet creation. Mirrors `kohaku wallet create eoa <name> [path]`
 *  + sets a passphrase via the daemon's `eoa.create` RPC. */
export default function CreateEoaFlow({ onDone }: Props) {
  const [params, setParams] = useState<Record<string, string> | null>(null);

  if (!params) {
    const fields: Field[] = [
      {
        name: "name",
        label: "Wallet name",
        placeholder: "e.g. mainEoa",
        validate: (v) =>
          NAME_RE.test(v)
            ? null
            : "1–64 chars: letters, digits, '-' or '_'; must start with alnum",
      },
      {
        name: "derivationPath",
        label: "Derivation path (optional)",
        placeholder: "m/44'/60'/0'/0/0",
        validate: (v) =>
          v.length === 0 || PATH_RE.test(v) ? null : "expected BIP-32 path or empty",
      },
      {
        name: "passphrase",
        label: "Passphrase",
        secret: true,
        validate: (v) =>
          v.length < 8 ? "passphrase must be at least 8 characters" : null,
      },
      {
        name: "confirm",
        label: "Confirm passphrase",
        secret: true,
        validate: (v) => (v.length === 0 ? "required" : null),
      },
    ];
    return (
      <Layout
        title="Create EOA wallet"
        subtitle="Generates a new BIP-39 mnemonic (24 words), encrypts it with your passphrase."
      >
        <Form
          fields={fields}
          onCancel={() => onDone(false)}
          onSubmit={(v) => {
            if (v.passphrase !== v.confirm) {
              // Re-render the form with an error. Cheap path: bail and let
              // the user re-enter; a richer impl would re-mount with the
              // validation embedded in the confirm field.
              setParams(null);
              return;
            }
            setParams({
              name: v.name ?? "",
              passphrase: v.passphrase ?? "",
              ...(v.derivationPath ? { derivationPath: v.derivationPath } : {}),
            });
          }}
        />
      </Layout>
    );
  }

  return (
    <RpcRunner
      title="Creating EOA wallet…"
      subtitle={`name: ${params.name}`}
      method="eoa.create"
      params={params}
      renderResult={(r: any) => (
        <Box flexDirection="column">
          <Text color={theme.ok}>✓ created</Text>
          <Text color={theme.dim}>address: {r?.address ?? "(unknown)"}</Text>
          <Text color={theme.dim}>derivation: {r?.derivationPath ?? "(default)"}</Text>
          <Text color={theme.warn}>
            ⚠ Reveal &amp; back up the mnemonic with: kohaku wallet show {params.name}
          </Text>
        </Box>
      )}
      onDone={onDone}
    />
  );
}
