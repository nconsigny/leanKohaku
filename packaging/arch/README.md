# Arch Linux packaging

`PKGBUILD` builds the Lean library, CLI, and daemon with the distro `lean4`
package and installs:

- `/usr/bin/leankohaku`
- `/usr/bin/leankohaku-daemon`

Before publishing, replace `_repo_url` and `url` with the canonical
leanKohaku repository URL. The `optdepends` entries are intentionally
host-integration tools only:

- `tpm2-tools` for TPM2 provisioning and inspection
- `libfido2` for FIDO2 security-key provisioning and inspection
- `fprintd` for optional biometric enrollment

The Lean modules do not link to those libraries or use them as crypto
implementations.
