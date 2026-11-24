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
    'Default: public downloads and verified local results; no prompt or token required.' \
    'For automatic result uploads, supply --token-file (0600) or a job-secret HF_TOKEN.'
   exit 0 ;;
  *) printf '%s\n' 'Unknown argument; use --help.' >&2; exit 2 ;;
 esac
done
BLUR_EPHEMERAL_TOKEN=''
trap '[[ -z "$BLUR_EPHEMERAL_TOKEN" ]] || rm -f -- "$BLUR_EPHEMERAL_TOKEN"' EXIT
if [[ "$BLUR_NEW_TOKEN" == 1 ]]; then
 printf '%s\n' 'No interactive input. Supply --token-file /private/token for uploads.' >&2
 exit 2
fi
if [[ -n "$BLUR_EXPLICIT_TOKEN" ]]; then
 [[ -f "$BLUR_EXPLICIT_TOKEN" && "$(stat -c '%a' "$BLUR_EXPLICIT_TOKEN")" == 600 ]] || { echo 'Token file must exist with mode 0600.' >&2; exit 2; }
 BLUR_HF_TOKEN_FILE="$(cd "$(dirname "$BLUR_EXPLICIT_TOKEN")" && pwd -P)/$(basename "$BLUR_EXPLICIT_TOKEN")"
 export BLUR_HF_TOKEN_FILE
elif [[ -n "${HF_TOKEN:-}" ]]; then
 BLUR_EPHEMERAL_TOKEN="$(mktemp "${TMPDIR:-/tmp}/hp1000-hf.XXXXXX")"
 printf '%s\n' "$HF_TOKEN" > "$BLUR_EPHEMERAL_TOKEN"
 chmod 600 "$BLUR_EPHEMERAL_TOKEN"
 export BLUR_HF_TOKEN_FILE="$BLUR_EPHEMERAL_TOKEN"
else
 unset BLUR_HF_TOKEN_FILE
 printf '%s\n' 'Public download mode: no Token or prompt. Verified results stay local; uploads require --token-file.'
fi
unset HF_TOKEN
export BLUR_PUBLIC_TOOLS="$BLUR_PROJECT_ROOT/tools"
mkdir -p "$BLUR_RUN_ROOT"
BLUR_RUN_ROOT="$(cd "$BLUR_RUN_ROOT" && pwd -P)"
chmod 700 "$BLUR_RUN_ROOT"
export BLUR_RUN_ROOT
bash "$BLUR_PROJECT_ROOT/launchers/$BLUR_MODE.sh"
