import { build } from "esbuild";

await build({
  entryPoints: ["src/index.tsx"],
  bundle: true,
  platform: "node",
  format: "esm",
  target: "node20",
  outfile: "dist/index.mjs",
  // Hashbang + a require shim. The ESM bundle pulls in a few CJS-style
  // deps (e.g. signal-exit) that call `require("node:assert")` at module
  // load time; reconstructing `require` from `import.meta.url` is the
  // standard esbuild workaround.
  banner: {
    js: [
      "#!/usr/bin/env node",
      "import { createRequire as __lkCreateRequire } from \"node:module\";",
      "import { fileURLToPath as __lkFileURLToPath } from \"node:url\";",
      "import { dirname as __lkDirname } from \"node:path\";",
      "const require = __lkCreateRequire(import.meta.url);",
      "const __filename = __lkFileURLToPath(import.meta.url);",
      "const __dirname = __lkDirname(__filename);",
      "",
    ].join("\n"),
  },
  // Ink and React import each other a lot; bundle everything so the
  // distributable is a single file with no node_modules dependency at
  // install time. Mirrors how `bridge/` ships node_modules but lets the
  // packaging step copy a single artifact.
  // `react-devtools-core` is a dev-only optional dep of Ink that we never
  // load at runtime. Alias it to an empty stub so the bundle is fully
  // self-contained and `node dist/index.mjs` works without any node_modules.
  alias: {
    "react-devtools-core": new URL("./src/empty.ts", import.meta.url).pathname,
  },
  define: {
    "process.env.NODE_ENV": "\"production\"",
  },
  logLevel: "info",
});
