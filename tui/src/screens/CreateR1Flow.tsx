import React, { useState } from "react";
import { Box, Text } from "ink";
import { Layout } from "../widgets/Layout.js";
import Form, { Field } from "../widgets/Form.js";
import RpcRunner from "../widgets/RpcRunner.js";
import { theme } from "../theme.js";

type Props = { onDone: (success: boolean) => void };

const NAME_RE = /^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$/;

/** Inline TPM/R1 wallet creation. The daemon will request fingerprint
 *  verification via `fprintd-verify` (gated by the local Linux TPM2
 *  hierarchy); progress is rendered live by RpcRunner from the daemon's
 *  `biometric-required` / `biometric-success` notifications. */
export default function CreateR1Flow({ onDone }: Props) {
  const [name, setName] = useState<string | null>(null);

  if (!name) {
    const fields: Field[] = [
      {
        name: "name",
        label: "Wallet name",
        placeholder: "e.g. daily-r1",
        validate: (v) =>
          NAME_RE.test(v)
            ? null
            : "1–64 chars: letters, digits, '-' or '_'; must start with alnum",
      },
    ];
    return (
      <Layout
        title="Create TPM/R1 wallet"
        subtitle="P-256 keypair generated inside the TPM. Touch the fingerprint reader when prompted."
      >
        <Form
          fields={fields}
          onCancel={() => onDone(false)}
          onSubmit={(v) => setName(v.name ?? null)}
        />
      </Layout>
    );
  }

  return (
    <RpcRunner
      title="Creating TPM/R1 wallet…"
      subtitle={`name: ${name} · biometric verification will be requested`}
      method="tpm.create"
      params={{ name }}
      renderResult={(r: any) => (
        <Box flexDirection="column">
          <Text color={theme.ok}>✓ created</Text>
          {r?.address && (
            <Text color={theme.dim}>address: {r.address}</Text>
          )}
          <Text color={theme.dim}>
            Deploy the smart-account wrapper with: kohaku wallet deploy {name}
          </Text>
        </Box>
      )}
      onDone={onDone}
    />
  );
}
