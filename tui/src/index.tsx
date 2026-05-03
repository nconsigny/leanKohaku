import React from "react";
import { render } from "ink";
import App from "./App.js";

if (!process.stdout.isTTY) {
  // eslint-disable-next-line no-console
  console.error(
    "leankohaku-tui: stdout is not a TTY. The interactive UI requires a real terminal — use `kohaku` for non-interactive commands.",
  );
  process.exit(2);
}

render(<App />);
