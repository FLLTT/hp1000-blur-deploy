#!/usr/bin/env bash
# Code-only entry. Credentials live outside the checkout and are never printed.
set +x
set -Eeuo pipefail
umask 077
BLUR_PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
BLUR_MODE=first
BLUR_RUN_ROOT="${BLUR_RUN_ROOT:-$BLUR_PROJECT_ROOT/.run}"
BLUR_EXPLICIT_TOKEN="${BLUR_HF_TOKEN_FILE:-}"
BLUR_NEW_TOKEN=0
while (($#)); do
 case "$1" in
  --all) BLUR_MODE=all; shift ;;
  --work-dir) [[ $# -ge 2 ]] || exit 2; BLUR_RUN_ROOT="$2"; shift 2 ;;
  --token-file) [[ $# -ge 2 ]] || exit 2; BLUR_EXPLICIT_TOKEN="$2"; shift 2 ;;
  --new-token) BLUR_NEW_TOKEN=1; shift ;;
  --help|-h)
   printf '%s\n' 'Usage: bash run.sh [--all] [--work-dir /scratch/path] [--token-file /private/token] [--new-token]' \
    'First run: paste the scoped Hugging Face token at the hidden prompt.' \
    'Later runs reuse the private local credential cache. No account login or sudo is required.'
   exit 0 ;;
  *) printf '%s\n' 'Unknown argument; use --help.' >&2; exit 2 ;;
 esac
done
BLUR_EPHEMERAL_TOKEN=''
trap '[[ -z "$BLUR_EPHEMERAL_TOKEN" ]] || rm -f -- "$BLUR_EPHEMERAL_TOKEN"' EXIT
blur_validate_token() {
 [[ "$1" =~ ^hf_[[:alnum:]_-]{10,}$ ]] || { printf '%s\n' 'Invalid Hugging Face token format; value was not saved or printed.' >&2; return 2; }
}
BLUR_CACHE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/humanplus-blur"
BLUR_CACHED_TOKEN="$BLUR_CACHE_DIR/token.private"
if [[ "$BLUR_NEW_TOKEN" == 0 && -n "$BLUR_EXPLICIT_TOKEN" ]]; then
 BLUR_HF_TOKEN_FILE="$BLUR_EXPLICIT_TOKEN"
elif [[ "$BLUR_NEW_TOKEN" == 0 && -n "${HF_TOKEN:-}" ]]; then
 blur_validate_token "$HF_TOKEN"
 BLUR_EPHEMERAL_TOKEN="$(mktemp "${TMPDIR:-/tmp}/hp1000-hf.XXXXXX")"
 printf '%s\n' "$HF_TOKEN" > "$BLUR_EPHEMERAL_TOKEN"
 chmod 600 "$BLUR_EPHEMERAL_TOKEN"
 BLUR_HF_TOKEN_FILE="$BLUR_EPHEMERAL_TOKEN"
elif [[ "$BLUR_NEW_TOKEN" == 0 && -f "$BLUR_CACHED_TOKEN" ]]; then
 BLUR_HF_TOKEN_FILE="$BLUR_CACHED_TOKEN"
else
 if ! { : </dev/tty; } 2>/dev/null; then
  printf '%s\n' 'No interactive terminal or cached credential. Supply --token-file /private/token (0600) or HF_TOKEN through the job secret environment.' >&2
  exit 2
 fi
 printf '%s\n' 'First run: the private HF dataset requires its scoped read/write token.' >/dev/tty
 IFS= read -r -s -p 'Paste HF Token (hidden), then press Enter: ' BLUR_TOKEN </dev/tty
 printf '\n' >/dev/tty
 blur_validate_token "$BLUR_TOKEN"
 mkdir -p "$BLUR_CACHE_DIR"
 chmod 700 "$BLUR_CACHE_DIR"
 BLUR_CANONICAL_CACHE="$(cd "$BLUR_CACHE_DIR" && pwd -P)"
 [[ "$BLUR_CANONICAL_CACHE" != "$BLUR_PROJECT_ROOT" && "$BLUR_CANONICAL_CACHE" != "$BLUR_PROJECT_ROOT/"* ]] || { printf '%s\n' 'Credential cache must be outside the Git checkout; set XDG_CONFIG_HOME accordingly.' >&2; exit 2; }
 BLUR_TOKEN_TMP="$(mktemp "$BLUR_CACHE_DIR/token.XXXXXX")"
 printf '%s\n' "$BLUR_TOKEN" > "$BLUR_TOKEN_TMP"
 chmod 600 "$BLUR_TOKEN_TMP"
 mv -f -- "$BLUR_TOKEN_TMP" "$BLUR_CACHED_TOKEN"
 unset BLUR_TOKEN
 BLUR_HF_TOKEN_FILE="$BLUR_CACHED_TOKEN"
 printf '%s\n' 'Credential saved privately outside the checkout; future runs reuse it.' >&2
fi
[[ -f "$BLUR_HF_TOKEN_FILE" && "$(stat -c '%a' "$BLUR_HF_TOKEN_FILE")" == 600 ]] || { printf '%s\n' 'Token file is missing or is not mode 0600. Set its permissions with chmod 600.' >&2; exit 2; }
IFS= read -r BLUR_CHECK_TOKEN < "$BLUR_HF_TOKEN_FILE" || true
blur_validate_token "$BLUR_CHECK_TOKEN"
unset BLUR_CHECK_TOKEN HF_TOKEN
BLUR_HF_TOKEN_FILE="$(cd -- "$(dirname -- "$BLUR_HF_TOKEN_FILE")" && pwd -P)/$(basename -- "$BLUR_HF_TOKEN_FILE")"
mkdir -p "$BLUR_RUN_ROOT"
BLUR_RUN_ROOT="$(cd "$BLUR_RUN_ROOT" && pwd -P)"
chmod 700 "$BLUR_RUN_ROOT"
export BLUR_HF_TOKEN_FILE BLUR_RUN_ROOT
bash "$BLUR_PROJECT_ROOT/launchers/$BLUR_MODE.sh"
