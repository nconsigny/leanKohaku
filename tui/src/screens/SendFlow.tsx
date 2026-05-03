import React, { useEffect, useState } from "react";
import { Box, Text, useInput } from "ink";
import Spinner from "ink-spinner";
import { Wallet } from "../types.js";
import { Layout, Banner } from "../widgets/Layout.js";
import Form, { Field } from "../widgets/Form.js";
import RpcRunner from "../widgets/RpcRunner.js";
import { call } from "../daemon.js";
import { theme } from "../theme.js";
import { formatEth, hexToBigInt, shortAddr } from "../format.js";

type Props = {
  wallet: Wallet;
  onDone: (success: boolean) => void;
};

type Phase =
  | { kind: "form" }
  | { kind: "resolving"; raw: string; amountEth: string; passphrase?: string }
  | {
      kind: "run";
      to: string;
      amountEth: string;
      passphrase?: string;
    }
  | { kind: "resolveError"; raw: string; message: string }
  | { kind: "unlockError"; message: string };

const ADDR_RE = /^0x[0-9a-fA-F]{40}$/;

function ethToWei(amountEth: string): bigint {
  const [whole, frac = ""] = amountEth.split(".");
  const fracPadded = (frac + "0".repeat(18)).slice(0, 18);
  return BigInt(whole || "0") * 10n ** 18n + BigInt(fracPadded || "0");
}

/** Send ETH from any wallet. EOA → eoa.send (passphrase prompt). TPM/R1 →
 *  r1.sendEthSepolia (biometric prompt streamed via notifications). */
export default function SendFlow({ wallet, onDone }: Props) {
  const [phase, setPhase] = useState<Phase>({ kind: "form" });

  if (phase.kind === "form") {
    const fields: Field[] = [
      {
        name: "to",
        label: "Recipient (0x… or ENS)",
        placeholder: "0xAa65… or vitalik.eth",
        validate: (v) =>
          v.length === 0
            ? "required"
            : v.startsWith("0x") && v.length !== 42
              ? "0x address must be 42 chars"
              : null,
      },
      {
        name: "amountEth",
        label: "Amount (ETH)",
        placeholder: "0.01",
        validate: (v) =>
          /^[0-9]+(\.[0-9]+)?$/.test(v) ? null : "expected a decimal ETH amount",
      },
      ...(wallet.kind === "eoa"
        ? [
            {
              name: "passphrase",
              label: `Passphrase for ${wallet.name}`,
              secret: true,
              validate: (v: string) => (v.length === 0 ? "required" : null),
            } as Field,
          ]
        : []),
    ];
    return (
      <Layout
        title={`Send from ${wallet.name}`}
        subtitle={`${shortAddr(wallet.address)} · ${
          wallet.balanceWei !== undefined ? formatEth(wallet.balanceWei) : "…"
        }`}
      >
        <Form
          fields={fields}
          onCancel={() => onDone(false)}
          onSubmit={(v) => {
            const raw = (v.to ?? "").trim();
            // If the user typed a 0x address, skip ENS resolution. Otherwise
            // resolve before dispatch — the daemon's send paths expect a
            // canonical 20-byte address and reject ENS literals.
            if (ADDR_RE.test(raw)) {
              setPhase({
                kind: "run",
                to: raw,
                amountEth: v.amountEth ?? "",
                passphrase: v.passphrase,
              });
            } else {
              setPhase({
                kind: "resolving",
                raw,
                amountEth: v.amountEth ?? "",
                passphrase: v.passphrase,
              });
            }
          }}
        />
      </Layout>
    );
  }

  if (phase.kind === "resolving") {
    return (
      <ResolveStep
        raw={phase.raw}
        onResolved={(addr) =>
          setPhase({
            kind: "run",
            to: addr,
            amountEth: phase.amountEth,
            passphrase: phase.passphrase,
          })
        }
        onError={(msg) =>
          setPhase({ kind: "resolveError", raw: phase.raw, message: msg })
        }
      />
    );
  }

  if (phase.kind === "resolveError") {
    return (
      <Layout
        title={`Could not resolve ${phase.raw}`}
        hint="esc • back"
      >
        <Banner kind="err" text={phase.message} />
        <BackOnEsc onDone={() => onDone(false)} />
      </Layout>
    );
  }

  if (phase.kind === "unlockError") {
    return (
      <Layout title="Unlock failed" hint="esc • back">
        <Banner kind="err" text={phase.message} />
        <BackOnEsc onDone={() => onDone(false)} />
      </Layout>
    );
  }

  // Dispatch.
  if (wallet.kind === "eoa") {
    return (
      <EoaSend
        wallet={wallet}
        to={phase.to}
        amountEth={phase.amountEth}
        passphrase={phase.passphrase ?? ""}
        onUnlockError={(msg) => setPhase({ kind: "unlockError", message: msg })}
        onDone={onDone}
      />
    );
  }
  // TPM/R1 — biometric is gated by the daemon and surfaced as notifications.
  return (
    <RpcRunner
      title={`Sending ${phase.amountEth} ETH from ${wallet.name} (TPM/R1)`}
      subtitle={`to ${phase.to} · biometric verification will be requested`}
      method="r1.sendEthSepolia"
      params={{
        name: wallet.name,
        to: phase.to,
        amountEth: phase.amountEth,
      }}
      renderResult={(r) => <SendResult result={r} />}
      onDone={onDone}
    />
  );
}

/** Unlock the EOA slot with the form-supplied passphrase, then dispatch
 *  eoa.send. Mirrors the CLI's callWithAutoUnlock behavior, except we have
 *  the passphrase up-front so we unlock unconditionally instead of waiting
 *  for a -32012 retry. */
type EoaPhase =
  | { kind: "unlocking" }
  | { kind: "simulating" }
  | { kind: "confirm"; decoded: any; sim: any }
  | { kind: "sending" };

function EoaSend({
  wallet,
  to,
  amountEth,
  passphrase,
  onUnlockError,
  onDone,
}: {
  wallet: Wallet;
  to: string;
  amountEth: string;
  passphrase: string;
  onUnlockError: (msg: string) => void;
  onDone: (success: boolean) => void;
}) {
  const [phase, setPhase] = useState<EoaPhase>({ kind: "unlocking" });
  const wei = ethToWei(amountEth);
  const valueHex = "0x" + wei.toString(16);

  // Step 1: unlock the slot. The passphrase came from the form one screen
  // up; submitting it to `eoa.unlock` rather than passing it into eoa.send
  // mirrors the CLI's auto-unlock pattern (Cli/Runtime.lean:430-447).
  useEffect(() => {
    if (phase.kind !== "unlocking") return;
    let cancelled = false;
    call("eoa.unlock", { name: wallet.name, passphrase }).then((r) => {
      if (cancelled) return;
      if (!r.ok) return onUnlockError(`${r.error.message} (code ${r.error.code})`);
      setPhase({ kind: "simulating" });
    });
    return () => {
      cancelled = true;
    };
  }, [phase.kind]);

  // Step 2: pre-sign clear-signing gate — decode + simulate before the user
  // authorizes any signing. For native ETH transfers calldata is "0x" so
  // the decoder returns no descriptor match (correct), but the simulator
  // still tells us the receipient exists / would-revert / gas estimate.
  // Phase 2 ERC-7730: every signed tx flows through this gate.
  useEffect(() => {
    if (phase.kind !== "simulating") return;
    let cancelled = false;
    Promise.all([
      call<any>("tx.decodeIntent", {
        chainId: 11155111,
        to,
        value: valueHex,
        data: "0x",
        from: wallet.address,
      }),
      call<any>("tx.simulate", {
        chainId: 11155111,
        to,
        value: valueHex,
        data: "0x",
        from: wallet.address,
        block: "latest",
      }),
    ]).then(([d, s]) => {
      if (cancelled) return;
      const decoded = d.ok ? (d.result?.result ?? d.result) : { matched: false };
      const sim = s.ok ? s.result : { ok: false, simRpcError: s.error.message };
      setPhase({ kind: "confirm", decoded, sim });
    });
    return () => {
      cancelled = true;
    };
  }, [phase.kind]);

  // Step 3: confirm screen. Enter advances to the actual eoa.send;
  // Esc bails out without signing. This is the load-bearing piece — the
  // user looks at the simulated effect, not the form they typed.
  if (phase.kind === "unlocking") {
    return (
      <Layout title={`Unlocking ${wallet.name}…`}>
        <Text>
          <Text color={theme.primary}>
            <Spinner type="dots" />
          </Text>{" "}
          <Text color={theme.dim}>verifying passphrase</Text>
        </Text>
      </Layout>
    );
  }
  if (phase.kind === "simulating") {
    return (
      <Layout title="Pre-sign check">
        <Text>
          <Text color={theme.primary}>
            <Spinner type="dots" />
          </Text>{" "}
          <Text color={theme.dim}>simulating transaction against the RPC node…</Text>
        </Text>
      </Layout>
    );
  }
  if (phase.kind === "confirm") {
    return (
      <ConfirmGate
        title={`Confirm: send ${amountEth} ETH from ${wallet.name}`}
        subtitle={`to ${to}`}
        decoded={phase.decoded}
        sim={phase.sim}
        onConfirm={() => setPhase({ kind: "sending" })}
        onCancel={() => onDone(false)}
      />
    );
  }
  return (
    <RpcRunner
      title={`Sending ${amountEth} ETH from ${wallet.name}`}
      subtitle={`to ${to}`}
      method="eoa.send"
      params={{
        name: wallet.name,
        to,
        value: wei,
      }}
      renderResult={(r) => <SendResult result={r} />}
      onDone={onDone}
    />
  );
}

/** Pre-sign confirmation. Renders the decoded intent + simulated effect
 *  together; Enter advances to signing, Esc cancels. The user is looking at
 *  ground truth (RPC simulation) rather than the form they typed. */
function ConfirmGate({
  title,
  subtitle,
  decoded,
  sim,
  onConfirm,
  onCancel,
}: {
  title: string;
  subtitle: string;
  decoded: any;
  sim: any;
  onConfirm: () => void;
  onCancel: () => void;
}) {
  useInput((_, key) => {
    if (key.return) onConfirm();
    if (key.escape) onCancel();
  });
  const okSim = sim?.ok === true;
  const matched = decoded?.matched === true;
  return (
    <Layout
      title={title}
      subtitle={subtitle}
      hint="enter — sign & broadcast · esc — cancel"
    >
      <Box flexDirection="column" marginBottom={1}>
        {matched ? (
          <>
            <Text>
              <Text color={theme.primary} bold>
                {decoded.intent ?? "(no intent)"}
              </Text>
            </Text>
            <Text color={theme.dim}>
              {decoded.contractName ?? "(contract)"} · {decoded.function}
            </Text>
            {(decoded.fields ?? []).map((f: any, i: number) => (
              <Text key={i}>
                <Text color={theme.dim}>{f.label.padEnd(14)}</Text>{" "}
                <Text>{f.formatted}</Text>
              </Text>
            ))}
          </>
        ) : (
          <Text color={theme.dim}>
            no descriptor matched · native ETH transfer (data = 0x)
          </Text>
        )}
      </Box>
      <Box flexDirection="column" marginBottom={1}>
        <Text>
          <Text color={theme.dim}>simulation: </Text>
          {sim?.simRpcError ? (
            <Text color={theme.warn}>(daemon error)</Text>
          ) : okSim ? (
            <Text color={theme.ok}>✓ would succeed</Text>
          ) : (
            <Text color={theme.err}>✗ would revert</Text>
          )}
        </Text>
        {sim?.gasEstimate && (
          <Text>
            <Text color={theme.dim}>gas: </Text>
            <Text>
              {(() => {
                try {
                  return BigInt(sim.gasEstimate).toString();
                } catch {
                  return sim.gasEstimate;
                }
              })()}{" "}
              units
            </Text>
          </Text>
        )}
        {sim?.revertReason && (
          <Box flexDirection="column">
            <Text color={theme.err}>revert: {String(sim.revertReason).slice(0, 200)}</Text>
          </Box>
        )}
        {sim?.simRpcError && (
          <Text color={theme.dim}>{sim.simRpcError}</Text>
        )}
      </Box>
      {!okSim && !sim?.simRpcError && (
        <Text color={theme.warn}>
          ⚠ Simulation failed. Pressing Enter will still broadcast — only
          do this if you understand why simulation is wrong.
        </Text>
      )}
    </Layout>
  );
}

function ResolveStep({
  raw,
  onResolved,
  onError,
}: {
  raw: string;
  onResolved: (addr: string) => void;
  onError: (msg: string) => void;
}) {
  useEffect(() => {
    let cancelled = false;
    call<{ address?: string }>("chain.resolveName", { name: raw }).then((r) => {
      if (cancelled) return;
      if (!r.ok) return onError(`ENS resolve failed: ${r.error.message}`);
      const addr = r.result?.address;
      if (!addr || !ADDR_RE.test(addr)) {
        return onError(`ENS '${raw}' did not resolve to a 0x address`);
      }
      onResolved(addr);
    });
    return () => {
      cancelled = true;
    };
  }, []);
  return (
    <Layout title={`Resolving ${raw}…`}>
      <Text>
        <Text color={theme.primary}>
          <Spinner type="dots" />
        </Text>{" "}
        <Text color={theme.dim}>asking the daemon to resolve ENS</Text>
      </Text>
    </Layout>
  );
}

function BackOnEsc({ onDone }: { onDone: () => void }) {
  useInput((_, key) => {
    if (key.return || key.escape) onDone();
  });
  return null;
}

function SendResult({ result }: { result: any }) {
  // Note: every row is its own <Text> wrapped in a <Box flexDirection="column">
  // so React fragments don't collapse multiple lines onto one row.
  const txHash = result?.txHash ?? "(no hash)";
  const status = result?.status ?? "(unknown)";
  const blockN = hexToBigInt(result?.blockNumber);
  const gasUsed = hexToBigInt(result?.gasUsed);
  const effPrice = hexToBigInt(result?.effectiveGasPrice);
  const valueWei =
    typeof result?.valueWei === "string"
      ? (() => {
          try {
            return BigInt(result.valueWei);
          } catch {
            return 0n;
          }
        })()
      : 0n;
  return (
    <Box flexDirection="column">
      <Text>
        <Text color={theme.dim}>tx:    </Text>
        {txHash}
      </Text>
      <Text>
        <Text color={theme.dim}>status:</Text>{" "}
        <Text color={status === "success" ? theme.ok : theme.err}>{status}</Text>
      </Text>
      {valueWei > 0n && (
        <Text>
          <Text color={theme.dim}>value: </Text>
          {formatEth(valueWei)}
        </Text>
      )}
      {blockN > 0n && (
        <Text>
          <Text color={theme.dim}>block: </Text>
          {blockN.toString()}
        </Text>
      )}
      {gasUsed > 0n && (
        <Text>
          <Text color={theme.dim}>gas:   </Text>
          {gasUsed.toString()}{" "}
          <Text color={theme.dim}>
            ({Number(effPrice) / 1e9} gwei)
          </Text>
        </Text>
      )}
      <Text color={theme.dim}>
        https://sepolia.etherscan.io/tx/{txHash}
      </Text>
    </Box>
  );
}
