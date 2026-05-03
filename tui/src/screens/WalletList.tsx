import React, { useEffect, useState } from "react";
import { Box, Text, useInput } from "ink";
import Spinner from "ink-spinner";
import { theme } from "../theme.js";
import { call } from "../daemon.js";
import {
  ChainBalance,
  EoaListEntry,
  TpmListEntry,
  Wallet,
} from "../types.js";
import { formatEth, hexToBigInt, shortAddr } from "../format.js";

type Props = {
  onSelect: (w: Wallet) => void;
  onQuit: () => void;
  /** Optional refresh trigger — bumping this re-fetches everything. Used
   *  after an inline action that may have changed balances. */
  refreshKey?: number;
};

/** Loads the wallet list from the daemon (eoa.list + tpm.listSepoliaAddresses)
 *  and fetches balances per row in parallel. Keys: ↑/↓ to move, Enter to
 *  select, q or Esc to quit. */
export default function WalletList({ onSelect, onQuit, refreshKey = 0 }: Props) {
  const [wallets, setWallets] = useState<Wallet[]>([]);
  const [cursor, setCursor] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Initial load: list wallets, then kick off per-row balance fetches.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      const eoaRes = await call<EoaListEntry[]>("eoa.list");
      const tpmRes = await call<TpmListEntry[]>("tpm.listSepoliaAddresses");
      if (cancelled) return;

      const out: Wallet[] = [];
      if (eoaRes.ok && Array.isArray(eoaRes.result)) {
        for (const e of eoaRes.result) {
          if (!e?.name || !e?.address) continue;
          out.push({
            kind: "eoa",
            name: e.name,
            address: e.address,
            unlocked: e.unlocked === true,
          });
        }
      }
      if (tpmRes.ok && Array.isArray(tpmRes.result)) {
        for (const t of tpmRes.result) {
          if (!t?.name || !t?.address) continue;
          out.push({ kind: "tpm", name: t.name, address: t.address });
        }
      }

      if (out.length === 0) {
        const failed = !eoaRes.ok ? eoaRes : !tpmRes.ok ? tpmRes : null;
        setError(
          failed && !failed.ok
            ? failed.error.message
            : "no wallets configured — run `kohaku wallet create eoa <name>` or `wallet create r1 <name>`",
        );
      }

      setWallets(out);
      setLoading(false);

      // Fan out balance fetches; update each row as it completes.
      out.forEach((w, i) => {
        call<ChainBalance>("chain.balance", { address: w.address }).then((r) => {
          if (cancelled) return;
          if (!r.ok) return;
          const wei = hexToBigInt(r.result?.balance);
          setWallets((prev) => {
            const copy = prev.slice();
            const cur = copy[i];
            if (cur) copy[i] = { ...cur, balanceWei: wei };
            return copy;
          });
        });
      });
    })();
    return () => {
      cancelled = true;
    };
  }, [refreshKey]);

  useInput((input, key) => {
    if (key.escape || input === "q") {
      onQuit();
      return;
    }
    if (key.upArrow || input === "k") {
      setCursor((c) => Math.max(0, c - 1));
      return;
    }
    if (key.downArrow || input === "j") {
      setCursor((c) => Math.min(wallets.length - 1, c + 1));
      return;
    }
    if (key.return) {
      const w = wallets[cursor];
      if (w) onSelect(w);
    }
  });

  return (
    <Box flexDirection="column" paddingX={1}>
      <Text color={theme.primary} bold>
        leanKohaku — wallets
      </Text>
      <Text color={theme.dim}>
        ↑/↓ move · enter select · q quit
      </Text>
      <Box marginTop={1} flexDirection="column">
        {loading && (
          <Text>
            <Text color={theme.primary}>
              <Spinner type="dots" />
            </Text>{" "}
            <Text color={theme.dim}>loading wallets…</Text>
          </Text>
        )}
        {error && <Text color={theme.err}>error: {error}</Text>}
        {wallets.map((w, i) => {
          const selected = i === cursor;
          const tag = w.kind === "eoa" ? "[eoa]" : "[tpm]";
          const bal =
            w.balanceWei === undefined ? "…" : formatEth(w.balanceWei);
          const lockedHint =
            w.kind === "eoa" && w.unlocked === false ? " [locked]" : "";
          return (
            <Box key={`${w.kind}:${w.name}`}>
              <Text color={selected ? theme.accent : undefined}>
                {selected ? "▶ " : "  "}
              </Text>
              <Text color={w.kind === "eoa" ? theme.primary : theme.ok}>
                {tag.padEnd(6)}
              </Text>
              <Text color={selected ? theme.accent : undefined} bold={selected}>
                {" "}
                {w.name.padEnd(18)}
              </Text>
              <Text color={theme.dim}>{shortAddr(w.address).padEnd(14)}</Text>
              <Text>{" "}{bal}</Text>
              {lockedHint && <Text color={theme.warn}>{lockedHint}</Text>}
            </Box>
          );
        })}
      </Box>
    </Box>
  );
}
