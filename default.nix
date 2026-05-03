{ pkgs ? import <nixpkgs> { } }:

pkgs.stdenv.mkDerivation rec {
  pname = "leankohaku";
  version = "0.1.0";

  src = pkgs.lib.cleanSource ./.;

  nativeBuildInputs = [
    pkgs.git
    pkgs.lean4
    pkgs.cmake
    pkgs.ninja
    pkgs.clang
    pkgs.nodejs_20
  ];

  buildPhase = ''
    runHook preBuild
    export HOME="$TMPDIR"
    lake build
    # TUI bundle (Ink/React → single esbuild output). Skipped silently if
    # tui/ is absent so the derivation still works for header-only checkouts.
    if [ -d tui ]; then
      ( cd tui && npm ci --offline --no-audit --no-fund 2>/dev/null || \
                  npm install --no-audit --no-fund )
      ( cd tui && npm run build )
    fi
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 .lake/build/bin/leankohaku "$out/bin/leankohaku"
    install -Dm755 .lake/build/bin/leankohaku-daemon "$out/bin/leankohaku-daemon"
    # Short alias users type interactively. Single binary on disk.
    ln -s leankohaku "$out/bin/kohaku"

    # Shell completion, generated from the binary so it tracks whatever
    # commands the build actually exposes (no second source of truth).
    install -dm755 "$out/share/bash-completion/completions"
    "$out/bin/leankohaku" completion bash \
        > "$out/share/bash-completion/completions/leankohaku"
    ln -s leankohaku "$out/share/bash-completion/completions/kohaku"

    install -dm755 "$out/share/zsh/site-functions"
    "$out/bin/leankohaku" completion zsh \
        > "$out/share/zsh/site-functions/_leankohaku"
    ln -s _leankohaku "$out/share/zsh/site-functions/_kohaku"

    if [ -f tui/dist/index.mjs ]; then
      install -Dm644 tui/dist/index.mjs "$out/share/leankohaku/tui/index.mjs"
    fi

    install -Dm644 packaging/systemd/leankohaku.socket "$out/lib/systemd/user/leankohaku.socket"
    install -Dm644 packaging/systemd/leankohaku.service "$out/lib/systemd/user/leankohaku.service"
    install -Dm644 README.md "$out/share/doc/leankohaku/README.md"
    install -Dm644 INVARIANTS.md "$out/share/doc/leankohaku/INVARIANTS.md"
    install -Dm644 SECURITY.md "$out/share/doc/leankohaku/SECURITY.md"
    install -Dm644 docs/CLI.md "$out/share/doc/leankohaku/CLI.md"
    install -Dm644 docs/DAEMON.md "$out/share/doc/leankohaku/DAEMON.md"
    install -Dm644 docs/PRIVACY_SECURITY.md "$out/share/doc/leankohaku/PRIVACY_SECURITY.md"
    install -Dm644 docs/R1_SEPOLIA.md "$out/share/doc/leankohaku/R1_SEPOLIA.md"
    runHook postInstall
  '';

  passthru = {
    leanToolchain = builtins.readFile ./lean-toolchain;
    optionalSystemIntegration = [
      "tpm2-tools"
      "libfido2"
      "fprintd"
    ];
  };

  meta = with pkgs.lib; {
    description = "Formally modeled Ethereum wallet daemon written in Lean 4";
    longDescription = ''
      leanKohaku builds the Lean library, CLI, and daemon without linking TPM2,
      FIDO2, Secure Enclave, or other crypto/runtime FFI libraries into the
      wallet. Linux TPM2, FIDO2, and keyring support is currently modeled as a
      local policy boundary; system packages such as tpm2-tools, libfido2, and
      fprintd are optional operator tooling for host provisioning and testing.
      HACL Packages is the only accepted external crypto dependency and is
      wired through script/setup_hacl.sh rather than linked into the default
      Lean build.
    '';
    mainProgram = "leankohaku";
    platforms = platforms.linux;
  };
}
