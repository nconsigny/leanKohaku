import React from "react";
import { Box, Text } from "ink";
import { theme } from "../theme.js";

/** Standard frame: title bar, optional subtitle, content, footer hint row. */
export function Layout(props: {
  title: string;
  subtitle?: string;
  hint?: string;
  children: React.ReactNode;
}) {
  return (
    <Box flexDirection="column" paddingX={1}>
      <Text color={theme.primary} bold>
        {props.title}
      </Text>
      {props.subtitle && <Text color={theme.dim}>{props.subtitle}</Text>}
      <Box marginTop={1} flexDirection="column">
        {props.children}
      </Box>
      {props.hint && (
        <Box marginTop={1}>
          <Text color={theme.dim}>{props.hint}</Text>
        </Box>
      )}
    </Box>
  );
}

/** Coloured one-line status: ok/warn/err. Used for inline result banners. */
export function Banner({
  kind,
  text,
}: {
  kind: "ok" | "warn" | "err" | "info";
  text: string;
}) {
  const color =
    kind === "ok"
      ? theme.ok
      : kind === "warn"
        ? theme.warn
        : kind === "err"
          ? theme.err
          : theme.primary;
  const glyph =
    kind === "ok" ? "✓" : kind === "warn" ? "⚠" : kind === "err" ? "✗" : "·";
  return (
    <Text color={color}>
      {glyph} {text}
    </Text>
  );
}
