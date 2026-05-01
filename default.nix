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
  ];

  buildPhase = ''
    runHook preBuild
    export HOME="$TMPDIR"
    lake build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 .lake/build/bin/leankohaku "$out/bin/leankohaku"
    install -Dm755 .lake/build/bin/leankohaku-daemon "$out/bin/leankohaku-daemon"
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
