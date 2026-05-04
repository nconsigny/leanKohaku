import React, { useEffect, useState } from "react";
import { useApp } from "ink";
import { call } from "./daemon.js";
import MainMenu, { MainAction } from "./screens/MainMenu.js";
import WalletList from "./screens/WalletList.js";
import ActionPicker, { Action as WalletAction } from "./screens/ActionPicker.js";
import SendFlow from "./screens/SendFlow.js";
import ShieldFlow from "./screens/ShieldFlow.js";
import CreateEoaFlow from "./screens/CreateEoaFlow.js";
import CreateR1Flow from "./screens/CreateR1Flow.js";
import ImportEoaFlow from "./screens/ImportEoaFlow.js";
import CreateWalletPicker, { CreateKind } from "./screens/CreateWalletPicker.js";
import ImportWalletPicker, { ImportKind } from "./screens/ImportWalletPicker.js";
import DecodeIntentFlow from "./screens/DecodeIntentFlow.js";
import LlmDraftFlow from "./screens/LlmDraftFlow.js";
import SendRawFlow from "./screens/SendRawFlow.js";
import DecodeTypedDataFlow from "./screens/DecodeTypedDataFlow.js";
import RevealMnemonicFlow from "./screens/RevealMnemonicFlow.js";
import PrivacyMenu from "./screens/PrivacyMenu.js";
import {
  LockToggleFlow,
  ResolveFlow,
  DaemonScreen,
  DetailsScreen,
  HistoryScreen,
  BalanceRefreshScreen,
  MoreCommandsScreen,
} from "./screens/SimpleFlows.js";
import { Wallet } from "./types.js";

type Screen =
  | { kind: "main" }
  | { kind: "wallets" }
  | { kind: "actions"; wallet: Wallet }
  | { kind: "send"; wallet: Wallet }
  | { kind: "shield"; wallet: Wallet }
  | { kind: "lock-toggle"; wallet: Wallet }
  | { kind: "reveal-mnemonic"; wallet: Wallet }
  | { kind: "details"; wallet: Wallet }
  | { kind: "history"; wallet: Wallet }
  | { kind: "balance-refresh"; wallet: Wallet }
  | { kind: "create-wallet" }
  | { kind: "create-eoa" }
  | { kind: "create-r1" }
  | { kind: "import-wallet" }
  | { kind: "import-eoa" }
  | { kind: "privacy" }
  | { kind: "resolve" }
  | { kind: "daemon" }
  | { kind: "more" }
  | { kind: "decode-intent" }
  | { kind: "llm-draft" }
  | { kind: "decode-typed-data" }
  | {
      kind: "send-raw";
      tx: { to: string; value: string; data: string; rationale?: string };
      chainId: number;
    };

/** Stack-based screen navigator. Push on navigate, pop on Esc/back; the
 *  bottom of the stack is the main menu so Quit always exits the app. */
export default function App() {
  const { exit } = useApp();
  const [stack, setStack] = useState<Screen[]>([{ kind: "main" }]);
  const [walletsRefreshKey, setWalletsRefreshKey] = useState(0);
  // Colibri stateless simulation runs the EVM locally inside a WASM light
  // client with committee-verified state proofs. Toggling here sends
  // daemon.colibri.toggle so the persistent sidecar lifecycle is owned by
  // the daemon (one bootstrap, reused across calls). Initial state pulls
  // from daemon.colibri.status; the env var is a convenience auto-enable
  // for power users.
  const [colibriEnabled, setColibriEnabled] = useState(false);
  const [colibriPending, setColibriPending] = useState(false);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const r = await call<{ running?: boolean }>("daemon.colibri.status", {});
      if (cancelled) return;
      if (r.ok && r.result?.running) setColibriEnabled(true);
      else if (process.env.KOHAKU_COLIBRI === "1") {
        // Power-user auto-enable: ask the daemon to spawn one.
        await call("daemon.colibri.toggle", { enable: true });
        if (!cancelled) setColibriEnabled(true);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  const toggleColibri = async () => {
    if (colibriPending) return;
    setColibriPending(true);
    const target = !colibriEnabled;
    const r = await call<{ running?: boolean }>("daemon.colibri.toggle", {
      enable: target,
    });
    if (r.ok) setColibriEnabled(r.result?.running === true);
    setColibriPending(false);
  };

  const top = stack[stack.length - 1]!;
  const push = (s: Screen) => setStack((prev) => [...prev, s]);
  const pop = () => {
    setStack((prev) => (prev.length > 1 ? prev.slice(0, -1) : prev));
  };

  const handleMain = (a: MainAction) => {
    switch (a) {
      case "wallets":         return push({ kind: "wallets" });
      case "create-wallet":   return push({ kind: "create-wallet" });
      case "import-wallet":   return push({ kind: "import-wallet" });
      case "privacy":         return push({ kind: "privacy" });
      case "daemon":          return push({ kind: "daemon" });
      case "toggle-colibri":  return void toggleColibri();
      case "more":            return push({ kind: "more" });
      case "quit":            return exit();
    }
  };

  const handleCreatePick = (k: CreateKind) => {
    if (k === "back") return pop();
    // Replace the picker on the stack with the chosen flow so Esc from the
    // form returns to MainMenu rather than back to the picker.
    setStack((prev) => [
      ...prev.slice(0, -1),
      k === "eoa" ? { kind: "create-eoa" } : { kind: "create-r1" },
    ]);
  };

  const handleImportPick = (k: ImportKind) => {
    if (k === "back") return pop();
    setStack((prev) => [...prev.slice(0, -1), { kind: "import-eoa" }]);
  };

  const handleWalletAction = (w: Wallet, a: WalletAction) => {
    switch (a) {
      case "send":             return push({ kind: "send", wallet: w });
      case "shield":           return push({ kind: "shield", wallet: w });
      case "lock-toggle":      return push({ kind: "lock-toggle", wallet: w });
      case "reveal-mnemonic":  return push({ kind: "reveal-mnemonic", wallet: w });
      case "details":          return push({ kind: "details", wallet: w });
      case "history":          return push({ kind: "history", wallet: w });
      case "balance-refresh":  return push({ kind: "balance-refresh", wallet: w });
      case "back":             return pop();
    }
  };

  // After any inline action that may have changed balances/lock state,
  // bump the refreshKey so the wallet list re-fetches when we land on it.
  const finishAction = () => {
    setWalletsRefreshKey((k) => k + 1);
    pop();
  };

  switch (top.kind) {
    case "main":
      return (
        <MainMenu
          onPick={handleMain}
          colibriEnabled={colibriEnabled}
          colibriPending={colibriPending}
        />
      );
    case "wallets":
      return (
        <WalletList
          refreshKey={walletsRefreshKey}
          onSelect={(w) => push({ kind: "actions", wallet: w })}
          onQuit={pop}
        />
      );
    case "actions":
      return (
        <ActionPicker
          wallet={top.wallet}
          onPick={(a) => handleWalletAction(top.wallet, a)}
          onBack={pop}
        />
      );
    case "send":
      return (
        <SendFlow
          wallet={top.wallet}
          colibriEnabled={colibriEnabled}
          onDone={finishAction}
        />
      );
    case "shield":
      return <ShieldFlow wallet={top.wallet} onDone={finishAction} />;
    case "lock-toggle":
      return <LockToggleFlow wallet={top.wallet} onDone={finishAction} />;
    case "reveal-mnemonic":
      return <RevealMnemonicFlow wallet={top.wallet} onDone={pop} />;
    case "details":
      return <DetailsScreen wallet={top.wallet} onDone={pop} />;
    case "history":
      return <HistoryScreen wallet={top.wallet} onDone={pop} />;
    case "balance-refresh":
      return <BalanceRefreshScreen wallet={top.wallet} onDone={finishAction} />;
    case "create-wallet":
      return <CreateWalletPicker onPick={handleCreatePick} />;
    case "create-eoa":
      return <CreateEoaFlow onDone={finishAction} />;
    case "create-r1":
      return <CreateR1Flow onDone={finishAction} />;
    case "import-wallet":
      return <ImportWalletPicker onPick={handleImportPick} />;
    case "import-eoa":
      return <ImportEoaFlow onDone={finishAction} />;
    case "privacy":
      return <PrivacyMenu onDone={pop} />;
    case "resolve":
      return <ResolveFlow onDone={pop} />;
    case "daemon":
      return <DaemonScreen onDone={pop} />;
    case "more":
      return (
        <MoreCommandsScreen
          onDone={pop}
          onPick={(a) => {
            if (a === "resolve") push({ kind: "resolve" });
            else if (a === "decode-intent") push({ kind: "decode-intent" });
            else if (a === "llm-draft") push({ kind: "llm-draft" });
            else if (a === "decode-typed-data") push({ kind: "decode-typed-data" });
          }}
        />
      );
    case "decode-intent":
      return <DecodeIntentFlow onDone={pop} />;
    case "llm-draft":
      return (
        <LlmDraftFlow
          onDone={pop}
          onApprove={(tx, chainId) => push({ kind: "send-raw", tx, chainId })}
        />
      );
    case "send-raw":
      return (
        <SendRawFlow
          tx={top.tx}
          chainId={top.chainId}
          onDone={finishAction}
        />
      );
    case "decode-typed-data":
      return <DecodeTypedDataFlow onDone={pop} />;
  }
}
