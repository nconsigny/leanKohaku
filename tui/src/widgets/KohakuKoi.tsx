/**
 * <KohakuKoi /> — render the Kohaku logo as half-block characters in any
 * Ink-based TUI. Each terminal cell encodes two stacked pixels via ▀/▄/█,
 * giving 2× vertical resolution at the typical 1:2 cell aspect ratio.
 *
 *   import KohakuKoi from "./widgets/KohakuKoi.js";
 *   <KohakuKoi size="medium" />
 *
 * No image-decoding deps — the cell grid is baked in (kohaku.cells.json).
 * Falls back to plain ASCII when `mono` is set, for terminals without
 * 24-bit color.
 */
import React from "react";
import { Box, Text } from "ink";
import cellsData from "./kohaku.cells.json" with { type: "json" };

type Cell = { ch: string; fg: string | null; bg: string | null };
type Grid = { width: number; height: number; rows: Cell[][] };
type Size = "medium" | "compact" | "tiny";

const GRIDS = cellsData as Record<Size, Grid>;

export interface KohakuKoiProps {
  /**
   * Render size:
   * - "medium"  : 60 cols × 30 rows (default)
   * - "compact" : 40 cols × 20 rows
   * - "tiny"    : 24 cols × 12 rows (denoised + eye preserved at this scale)
   */
  size?: Size;
  /** Render in monochrome ASCII (for terminals without truecolor). */
  mono?: boolean;
  /** Override the navy color used for outline + dark accents. */
  navy?: string;
  /** Override the red used for koi markings. */
  red?: string;
  /** Override the cream body color. */
  cream?: string;
}

const BRAND = {
  "#0f2a3f": "navy",
  "#c92a2a": "red",
  "#f5efe0": "cream",
} as const;

function recolor(
  hex: string | null,
  overrides: { navy?: string; red?: string; cream?: string },
): string | undefined {
  if (!hex) return undefined;
  const lower = hex.toLowerCase() as keyof typeof BRAND;
  const slot = BRAND[lower];
  if (slot && overrides[slot]) return overrides[slot];
  return hex;
}

// Group consecutive cells with the same (fg, bg) into single <Text> runs.
// One <Text> per cell still works but produces a much larger React tree
// and slower diffs; a 60-wide row typically collapses to ~10 runs.
function compactRow(row: Cell[]): { fg?: string; bg?: string; text: string }[] {
  const runs: { fg?: string; bg?: string; text: string }[] = [];
  let cur: { fg?: string; bg?: string; text: string } | null = null;
  for (const c of row) {
    const fg = c.fg ?? undefined;
    const bg = c.bg ?? undefined;
    if (cur && cur.fg === fg && cur.bg === bg) cur.text += c.ch;
    else {
      cur = { fg, bg, text: c.ch };
      runs.push(cur);
    }
  }
  return runs;
}

const KohakuKoi: React.FC<KohakuKoiProps> = ({
  size = "medium",
  mono = false,
  navy,
  red,
  cream,
}) => {
  const grid = GRIDS[size];
  const overrides = { navy, red, cream };

  if (mono) {
    // Brightness-mapped ASCII: navy=#, red=*, cream=., bg=space.
    const lines: string[] = grid.rows.map((row) =>
      row
        .map((c) => {
          if (!c.fg && !c.bg) return " ";
          const color = (c.fg ?? c.bg)?.toLowerCase();
          if (color === "#0f2a3f") return "#";
          if (color === "#c92a2a") return "*";
          return ".";
        })
        .join(""),
    );
    return (
      <Box flexDirection="column">
        {lines.map((l, i) => (
          <Text key={i}>{l}</Text>
        ))}
      </Box>
    );
  }

  return (
    <Box flexDirection="column">
      {grid.rows.map((row, y) => (
        <Text key={y}>
          {compactRow(row).map((run, i) => (
            <Text
              key={i}
              color={recolor(run.fg ?? null, overrides)}
              backgroundColor={recolor(run.bg ?? null, overrides)}
            >
              {run.text}
            </Text>
          ))}
        </Text>
      ))}
    </Box>
  );
};

export default KohakuKoi;
