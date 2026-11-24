#!/usr/bin/env bash
# Filled by sender after publishing an immutable deployment archive to the private repo.
set -Eeuo pipefail
umask 077
BLUR_LAUNCH_ROOT="${BLUR_RUN_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)}"
BLUR_REPO='FLTTY/Lty-HP1000'
BLUR_REVISION='ae81dc9b5ec9687443f7534ce6b9012eb8342288'
BLUR_PACKAGE='deployments/b65139c4302b91446f5d3751680a286f3ce63194ccc3ce2c85b98554da9ce423/bundle.tar'
BLUR_PACKAGE_SHA='b65139c4302b91446f5d3751680a286f3ce63194ccc3ce2c85b98554da9ce423'
BLUR_CONFIG_PATH='deployments/tasks/6c9da16e044b946372a89faaa118a2cd04c4ffb3ee69ef57b6d62a0320b75aa5.json'
command -v curl >/dev/null || command -v wget >/dev/null || { printf '%s\n' 'Download launcher needs curl or wget; offline archive/run.sh is also supported.' >&2; exit 2; }
[[ "$BLUR_PACKAGE_SHA" =~ ^[0-9a-f]{64}$ && "$BLUR_REVISION" =~ ^[0-9a-f]{40}$ ]] || { printf '%s\n' 'Sender must configure this launcher before delivery.' >&2; exit 2; }
mkdir -p "$BLUR_LAUNCH_ROOT/deployment"
exec 9>"$BLUR_LAUNCH_ROOT/deployment/launcher.lock"
flock -n 9 || exit 75
BLUR_HEADER_FILE="$(mktemp "$BLUR_LAUNCH_ROOT/deployment/header.XXXXXX")"
BLUR_DOWNLOAD_TMP="$(mktemp -d "$BLUR_LAUNCH_ROOT/deployment/download.XXXXXX")"
trap 'rm -f -- "$BLUR_HEADER_FILE"; rm -rf -- "$BLUR_DOWNLOAD_TMP"' EXIT
if [[ -n "${BLUR_HF_TOKEN_FILE:-}" ]]; then
 IFS= read -r BLUR_TOKEN < "$BLUR_HF_TOKEN_FILE" || true
 printf 'Authorization: Bearer %s\n' "$BLUR_TOKEN" > "$BLUR_HEADER_FILE"
 unset BLUR_TOKEN
else
 : > "$BLUR_HEADER_FILE"
fi
blur_download() {
 local BLUR_URL="$1" BLUR_DEST="$2" BLUR_STEP BLUR_CODE BLUR_NEXT
 if command -v curl >/dev/null; then
  curl --fail --silent --show-error --location --retry 3 --connect-timeout 20 --continue-at - \
   --header "@$BLUR_HEADER_FILE" "$BLUR_URL" --output "$BLUR_DEST"
  return
 fi
 # Authenticate only to huggingface.co. Never forward the HF token to a CDN.
 : > "$BLUR_DOWNLOAD_TMP/wget-auth"
 [[ ! -s "$BLUR_HEADER_FILE" ]] || printf 'header = %s\n' "$(cat "$BLUR_HEADER_FILE")" > "$BLUR_DOWNLOAD_TMP/wget-auth"
 for BLUR_STEP in 1 2 3 4 5 6 7 8; do
  printf '%s\n' "$BLUR_URL" > "$BLUR_DOWNLOAD_TMP/url"
  if [[ "$BLUR_URL" != https://huggingface.co/* ]]; then
   [[ "$BLUR_URL" == https://* ]] || return 1
   wget --quiet --no-hsts --timeout=120 --tries=3 --continue \
    --input-file="$BLUR_DOWNLOAD_TMP/url" -O "$BLUR_DEST"
   return
  fi
  BLUR_CODE=0
  wget --config="$BLUR_DOWNLOAD_TMP/wget-auth" --no-hsts --timeout=60 --tries=2 \
   --max-redirect=0 --server-response --input-file="$BLUR_DOWNLOAD_TMP/url" \
   -O "$BLUR_DOWNLOAD_TMP/body" 2> "$BLUR_DOWNLOAD_TMP/headers" || BLUR_CODE=$?
  if [[ "$BLUR_CODE" == 0 ]]; then
   mv "$BLUR_DOWNLOAD_TMP/body" "$BLUR_DEST"
   return
  fi
  BLUR_NEXT="$(sed -n 's/^[[:space:]]*[Ll]ocation:[[:space:]]*//p' "$BLUR_DOWNLOAD_TMP/headers" | tail -n 1 | sed 's/[[:space:]]*\[following\]$//;s/\r$//')"
  [[ "$BLUR_NEXT" == https://* && "$BLUR_NEXT" != *$'\n'* ]] || return 1
  BLUR_URL="$BLUR_NEXT"
 done
 return 1
}
BLUR_RELEASE_DIR="$BLUR_LAUNCH_ROOT/deployment/$BLUR_PACKAGE_SHA"
mkdir -p "$BLUR_RELEASE_DIR"
BLUR_ARCHIVE="$BLUR_RELEASE_DIR/bundle.tar"
BLUR_PARTS_DIR="$BLUR_RELEASE_DIR/parts"
mkdir -p "$BLUR_PARTS_DIR"
if [[ ! -f "$BLUR_ARCHIVE" ]] || [[ "$(sha256sum "$BLUR_ARCHIVE" | cut -d ' ' -f 1)" != "$BLUR_PACKAGE_SHA" ]]; then
 BLUR_OFFSET=0
 while read -r BLUR_PART_NAME BLUR_PART_SHA BLUR_PART_BYTES; do
  BLUR_PART_FILE="$BLUR_PARTS_DIR/$BLUR_PART_NAME"
  if [[ ! -f "$BLUR_PART_FILE" || "$(sha256sum "$BLUR_PART_FILE" | cut -d ' ' -f 1)" != "$BLUR_PART_SHA" ]]; then
   # Salvage a complete, independently checked block from an interrupted whole-file download.
   if [[ -f "$BLUR_ARCHIVE.partial" && "$(stat -c '%s' "$BLUR_ARCHIVE.partial")" -ge "$((BLUR_OFFSET + BLUR_PART_BYTES))" ]]; then
    dd if="$BLUR_ARCHIVE.partial" of="$BLUR_PART_FILE.seed" iflag=skip_bytes,count_bytes skip="$BLUR_OFFSET" count="$BLUR_PART_BYTES" status=none
    if [[ "$(sha256sum "$BLUR_PART_FILE.seed" | cut -d ' ' -f 1)" == "$BLUR_PART_SHA" ]]; then mv "$BLUR_PART_FILE.seed" "$BLUR_PART_FILE"; fi
   fi
   if [[ ! -f "$BLUR_PART_FILE" ]]; then
    printf 'Downloading deployment block %s\n' "$BLUR_PART_NAME"
    blur_download "https://huggingface.co/datasets/$BLUR_REPO/resolve/787cc07aeb4cc1213cf3c333f7ae394545976023/deployments/b65139c4302b91446f5d3751680a286f3ce63194ccc3ce2c85b98554da9ce423/parts/$BLUR_PART_NAME" "$BLUR_PART_FILE.partial" > "$BLUR_LAUNCH_ROOT/deployment/$BLUR_PART_NAME.log" 2>&1
    [[ "$(sha256sum "$BLUR_PART_FILE.partial" | cut -d ' ' -f 1)" == "$BLUR_PART_SHA" ]] || { printf '%s\n' 'Deployment block SHA mismatch; preserved.' >&2; exit 1; }
    mv "$BLUR_PART_FILE.partial" "$BLUR_PART_FILE"
   fi
  fi
  BLUR_OFFSET="$((BLUR_OFFSET + BLUR_PART_BYTES))"
 done <<'BLUR_PART_MANIFEST'
part-000 2f1e631c3bc1c0f4fec0357af4497921a73441b5d14f0f995b88b9f0e96ba0f6 268435456
part-001 f0147a013eb1a71f48d231a60fb7fa0cfd119c0956f389edaccd861086b9e8d5 268435456
part-002 2d3849c85c5c29674fffec79e7cc62a13741c6d6abd2a2b853a40c56e49cf6b8 268435456
part-003 35fa70fd6599c6ba73ea6e1ac673ef5a2595dfaac787e2060e1e9d1b4f090abb 268435456
part-004 23ad4c90c06c438e11b46ca57ff4df89bf3609f9bfb400e15d14e87c7c49e41c 268435456
part-005 2dadba983d3ff453074563de10ff97b4ce4ee295377b09a7899b30920ce27f63 268435456
part-006 0df7ff7d5108814bf86353bf25ddaf12b58232ce2302b85bd89c515ee2277f21 268435456
part-007 4f1a468af830ee29e693dcffafe69f19a812789b45610c48b0ed0989f721c89a 268435456
part-008 8589d23cccc3b6cea10336d192c58996d8e366824ef59710361f06d7a0b04470 268435456
part-009 cec1f22e02b126989d15430759bb843559b849a66a78ac7c5dc21dc2caa653e2 268435456
part-010 2b5167dbd9c69dab9315dd640108d25e5937a2b386a0027c46e38956c0277b49 268435456
part-011 7466a6bd27a09c4b40f70e18a273ebe9519c7f5153ad83f6e2b38c29f50ba4f1 268435456
part-012 0c1749c625adda29c4641330664337554fef662c9088728d78dcbe240375bb46 268435456
part-013 e61cf1e54503c465d3735501bfd4f2551a28c5734bfa5daa5a17debbcc36f182 268435456
part-014 64987e8037f7bc4c32061387a0a55bf830e941e6ee6fe422d004c92d00a1d495 268435456
part-015 dffafce4621dd86820ac22554bd32c3258c937a4e1de1d0944f3414cec982e40 268435456
part-016 6bacc1df5f49b7cd4e7512f088723e5843ca0bfa96042ba2fa2aa3ce285fc4e3 268435456
part-017 3f47c278599ecdd0bd3ff3e746c007d1a00ef670abbece44a96f4404a6f53ad1 130684928
BLUR_PART_MANIFEST
 cat "$BLUR_PARTS_DIR"/part-[0-9][0-9][0-9] > "$BLUR_ARCHIVE.new"
 [[ "$(sha256sum "$BLUR_ARCHIVE.new" | cut -d ' ' -f 1)" == "$BLUR_PACKAGE_SHA" ]] || { printf '%s\n' 'Reassembled archive SHA mismatch; preserved.' >&2; exit 1; }
 mv "$BLUR_ARCHIVE.new" "$BLUR_ARCHIVE"
fi
if [[ ! -d "$BLUR_RELEASE_DIR/humanplus-blur-hf-v2" ]]; then
 tar -xf "$BLUR_ARCHIVE" --no-same-owner -C "$BLUR_RELEASE_DIR"
fi
# The task JSON has no credentials. Fetch it at the same immutable release revision.
blur_download "https://huggingface.co/datasets/$BLUR_REPO/resolve/$BLUR_REVISION/$BLUR_CONFIG_PATH" \
 "$BLUR_DOWNLOAD_TMP/job.private.json" > "$BLUR_LAUNCH_ROOT/deployment/config-download.log" 2>&1
mv "$BLUR_DOWNLOAD_TMP/job.private.json" "$BLUR_LAUNCH_ROOT/deployment/job.private.json"
BLUR_BASE_PAYLOAD="$BLUR_RELEASE_DIR/humanplus-blur-hf-v2"
BLUR_OVERLAY_PAYLOAD="$BLUR_RELEASE_DIR/overlay-d8f89b2affb717ffacea0451e6ba6823b725d281e1714350951bdb7f0185c5d6/humanplus-blur-hf-v2"
if [[ ! -d "$BLUR_OVERLAY_PAYLOAD" ]]; then
 mkdir -p "$BLUR_OVERLAY_PAYLOAD"
 cp -al "$BLUR_BASE_PAYLOAD/." "$BLUR_OVERLAY_PAYLOAD/"
fi
BLUR_CURRENT_TRANSPORT="$(sha256sum "$BLUR_OVERLAY_PAYLOAD/hf_transport.py" | cut -d ' ' -f 1)"
if [[ "$BLUR_CURRENT_TRANSPORT" == '43e2b10fe2f1944f4df57b03f843be8722f4dc286e11090e92e46eddb1d818e9' ]]; then
 (cd "$BLUR_OVERLAY_PAYLOAD" && sha256sum --quiet --check SHA256SUMS)
 blur_download "https://huggingface.co/datasets/$BLUR_REPO/resolve/a74cf1e7a3402f5ce698b00404b50b42c5e04926/deployments/transport-overlay/d8f89b2affb717ffacea0451e6ba6823b725d281e1714350951bdb7f0185c5d6/hf_transport.py" "$BLUR_DOWNLOAD_TMP/hf_transport.py"
 [[ "$(sha256sum "$BLUR_DOWNLOAD_TMP/hf_transport.py" | cut -d ' ' -f 1)" == 'd8f89b2affb717ffacea0451e6ba6823b725d281e1714350951bdb7f0185c5d6' ]] || exit 1
 mv "$BLUR_DOWNLOAD_TMP/hf_transport.py" "$BLUR_OVERLAY_PAYLOAD/hf_transport.py"
 sed 's/^43e2b10fe2f1944f4df57b03f843be8722f4dc286e11090e92e46eddb1d818e9  hf_transport.py$/d8f89b2affb717ffacea0451e6ba6823b725d281e1714350951bdb7f0185c5d6  hf_transport.py/' "$BLUR_OVERLAY_PAYLOAD/SHA256SUMS" > "$BLUR_OVERLAY_PAYLOAD/SHA256SUMS.overlay"
 mv "$BLUR_OVERLAY_PAYLOAD/SHA256SUMS.overlay" "$BLUR_OVERLAY_PAYLOAD/SHA256SUMS"
 [[ "$(sha256sum "$BLUR_BASE_PAYLOAD/hf_transport.py" | cut -d ' ' -f 1)" == '43e2b10fe2f1944f4df57b03f843be8722f4dc286e11090e92e46eddb1d818e9' ]] || { printf '%s\n' 'Base deployment changed unexpectedly.' >&2; exit 1; }
 printf '%s\n' 'd8f89b2affb717ffacea0451e6ba6823b725d281e1714350951bdb7f0185c5d6' > "$BLUR_OVERLAY_PAYLOAD/TRANSPORT_OVERLAY_SHA256"
elif [[ "$BLUR_CURRENT_TRANSPORT" != 'd8f89b2affb717ffacea0451e6ba6823b725d281e1714350951bdb7f0185c5d6' ]]; then
 printf '%s\n' 'Unexpected transport version; preserved without overwrite.' >&2
 exit 1
fi
BLUR_PUBLIC_PAYLOAD="$BLUR_RELEASE_DIR/public-r1/humanplus-blur-hf-v2"
if [[ ! -d "$BLUR_PUBLIC_PAYLOAD" ]]; then
 mkdir -p "$BLUR_PUBLIC_PAYLOAD"
 cp -al "$BLUR_OVERLAY_PAYLOAD/." "$BLUR_PUBLIC_PAYLOAD/"
fi
bash "$BLUR_OVERLAY_PAYLOAD/run.sh" --setup-only \
 "$BLUR_LAUNCH_ROOT/deployment/job.private.json" "$BLUR_LAUNCH_ROOT/work-public-r1"
"$BLUR_LAUNCH_ROOT/work-public-r1/environment/bin/python" "$BLUR_PUBLIC_TOOLS/configure_public.py" "$BLUR_PUBLIC_PAYLOAD"
BLUR_OVERLAY_PAYLOAD="$BLUR_PUBLIC_PAYLOAD"
if [[ "${BLUR_PREPARE_ONLY:-0}" == 1 ]]; then echo "Software verified; no worker started."; exit 0; fi
bash "$BLUR_OVERLAY_PAYLOAD/run.sh" \
 "$BLUR_LAUNCH_ROOT/deployment/job.private.json" "$BLUR_LAUNCH_ROOT/work-public-r1"
