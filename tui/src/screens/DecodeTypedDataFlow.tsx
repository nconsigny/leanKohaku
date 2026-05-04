import React, { useEffect, useState } from "react";
import { Box, Text, useInput } from "ink";
import Spinner from "ink-spinner";
import { Layout, Banner } from "../widgets/Layout.js";
import Form, { Field } from "../widgets/Form.js";
import { call } from "../daemon.js";
import { theme } from "../theme.js";

type Props = { onDone: (s: boolean) => void };

type Phase =
  | { kind: "form" }
  | { kind: "running"; payload: any }
  | { kind: "ok"; result: any }
  | { kind: "err"; message: string };

/** Decode an EIP-712 typed-data message via `eip712.decodeIntent`. The form
 *  takes the full typed-data JSON (the same blob a dApp would pass to
 *  `eth_signTypedData_v4`) — too big for a textarea so users paste it.
 *  Pasted JSON gets parsed once and forwarded verbatim. */
export default function DecodeTypedDataFlow({ onDone }: Props) {
  const [phase, setPhase] = useState<Phase>({ kind: "form" });

  if (phase.kind === "form") {
    const fields: Field[] = [
      {
        name: "json",
        label: "Typed-data JSON (eth_signTypedData_v4 shape)",
        placeholder: '{"domain":{...},"types":{...},"primaryType":"...","message":{...}}',
        validate: (v) => {
          if (v.trim().length === 0) return "required";
          try {
            const o = JSON.parse(v);
            if (!o.domain || !o.types || !o.primaryType || !o.message) {
              return "missing one of: domain / types / primaryType / message";
            }
            return null;
          } catch (e: any) {
            return `invalid JSON: ${e?.message ?? "parse error"}`;
          }
        },
      },
    ];
    return (
      <Layout
        title="Decode typed data (EIP-712)"
        subtitle="Paste an eth_signTypedData_v4 payload to see the rendered intent."
        hint="enter — submit · esc — back"
      >
        <Form
          fields={fields}
          onCancel={() => onDone(false)}
          onSubmit={(v) => {
            try {
              const payload = JSON.parse(v.json ?? "");
              setPhase({ kind: "running", payload });
            } catch (e: any) {
              setPhase({ kind: "err", message: `parse failed: ${e?.message}` });
            }
          }}
        />
      </Layout>
    );
  }

  if (phase.kind === "running") {
    return <Runner payload={phase.payload} setPhase={setPhase} />;
  }

  if (phase.kind === "err") {
    return (
      <Layout title="Decode failed" hint="enter / esc — back">
        <Banner kind="err" text={phase.message} />
        <BackOnInput onDone={() => onDone(false)} />
      </Layout>
    );
  }

  return (
    <Layout title="Typed-data intent" hint="enter / esc — back">
      <DecodedView result={phase.result} />
      <BackOnInput onDone={() => onDone(false)} />
    </Layout>
  );
}

function Runner({
  payload,
  setPhase,
}: {
  payload: any;
  setPhase: (p: Phase) => void;
}) {
  useEffect(() => {
    let cancelled = false;
    const chainId =
      typeof payload?.domain?.chainId === "number"
        ? payload.domain.chainId
        : Number(payload?.domain?.chainId ?? 1);
    call<any>("eip712.decodeIntent", {
      chainId,
      domain: payload.domain,
      types: payload.types,
      primaryType: payload.primaryType,
      message: payload.message,
    }).then((r) => {
      if (cancelled) return;
      if (!r.ok) return setPhase({ kind: "err", message: r.error.message });
      const inner = r.result?.result ?? r.result;
      if (inner?.ok === false) {
        return setPhase({
          kind: "err",
          message: inner.error?.message ?? "decode failed",
        });
      }
      setPhase({ kind: "ok", result: inner });
    });
    return () => {
      cancelled = true;
    };
  }, []);
  return (
    <Layout title="Decoding…">
      <Text>
        <Text color={theme.primary}>
          <Spinner type="dots" />
        </Text>{" "}
        <Text color={theme.dim}>looking up descriptor by domain.verifyingContract</Text>
      </Text>
    </Layout>
  );
}

function DecodedView({ result }: { result: any }) {
  if (!result) return <Banner kind="warn" text="(empty response)" />;
  if (result.matched === false) {
    return (
      <Box flexDirection="column">
        <Banner kind="warn" text="No descriptor matched." />
        <Text color={theme.dim}>{result.reason}</Text>
        <Text color={theme.dim}>
          The Lean side needs an ERC-7730 descriptor with `context.eip712`
          covering this (chainId, verifyingContract). Bundle one in
          `bridge/clearsign/registry/`.
        </Text>
      </Box>
    );
  }
  return (
    <Box flexDirection="column">
      <Text>
        <Text color={theme.primary} bold>
          {result.intent ?? "(no intent)"}
        </Text>
      </Text>
      <Text color={theme.dim}>
        {result.contractName ?? "(typed data)"}
        {result.owner ? ` · ${result.owner}` : ""}
        {result.source ? ` · from ${result.source}` : ""}
      </Text>
      <Text color={theme.dim}>primary type: {result.primaryType}</Text>
      <Box marginTop={1} flexDirection="column">
        {(result.fields ?? []).map((f: any, i: number) => (
          <Text key={i}>
            <Text color={theme.dim}>{f.label.padEnd(14)}</Text>{" "}
            <Text>{f.formatted}</Text>
          </Text>
        ))}
      </Box>
    </Box>
  );
}

function BackOnInput({ onDone }: { onDone: () => void }) {
  useInput((_, key) => {
    if (key.return || key.escape) onDone();
  });
  return null;
}
