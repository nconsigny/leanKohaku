#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CLIENT_ROOT="LeanKohaku/Lib/Client.lean"
APP_ROOT="LeanKohaku/App/Main.lean"

if grep -REn '^import LeanKohaku\.(Wallet|Crypto|Keystore|Privacy|Daemon)' "$APP_ROOT" "$CLIENT_ROOT" LeanKohaku/Cli; then
  printf 'CLI isolation failed: forbidden runtime import in app/client roots or LeanKohaku/Cli\n' >&2
  exit 1
fi

if grep -REn '^import LeanKohaku$' "$APP_ROOT" "$CLIENT_ROOT" LeanKohaku/Cli; then
  printf 'CLI isolation failed: CLI imports root LeanKohaku module\n' >&2
  exit 1
fi

if ! grep -q '^import LeanKohaku.Lib.Client$' "$APP_ROOT"; then
  printf 'CLI isolation failed: app root must import LeanKohaku.Lib.Client\n' >&2
  exit 1
fi

if grep -E '^import ' "$APP_ROOT" | grep -Ev '^import LeanKohaku\.Lib\.Client$' | grep -q .; then
  printf 'CLI isolation failed: app root must not import anything except LeanKohaku.Lib.Client\n' >&2
  exit 1
fi

seen=""
check_no_transitive_keystore() {
  local module="$1"
  case " $seen " in
    *" $module "*) return 0 ;;
  esac
  seen="$seen $module"

  local path="${module//.//}.lean"
  if [[ ! -f "$path" ]]; then
    return 0
  fi

  while IFS= read -r imported; do
    if [[ "$imported" == LeanKohaku.Keystore* || "$imported" == LeanKohaku.Daemon* ]]; then
      printf 'CLI isolation failed: %s transitively imports %s\n' "$module" "$imported" >&2
      exit 1
    fi
    check_no_transitive_keystore "$imported"
  done < <(sed -n 's/^import[[:space:]]\+\([^[:space:]]\+\)$/\1/p' "$path")
}

check_no_transitive_keystore LeanKohaku.App.Main

printf 'CLI isolation checks passed\n'
