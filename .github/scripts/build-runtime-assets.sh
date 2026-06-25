#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${1:-${ROOT}/dist}"
XRAY_VERSION="${KOKORO_XRAY_VERSION:-v26.6.1}"
TARGET_ARCH="${KOKORO_ASSET_ARCH:-}"

if [[ -z "$TARGET_ARCH" ]]; then
    case "$(uname -m)" in
        x86_64) TARGET_ARCH="amd64" ;;
        aarch64|arm64) TARGET_ARCH="arm64" ;;
        *)
            echo "unsupported arch: $(uname -m)" >&2
            exit 1
            ;;
    esac
fi

case "$TARGET_ARCH" in
    amd64)
        xray_arch="64"
        asset_arch="amd64"
        ;;
    arm64)
        xray_arch="arm64-v8a"
        asset_arch="arm64"
        ;;
    *)
        echo "unsupported target arch: $TARGET_ARCH" >&2
        exit 1
        ;;
esac

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

extract_zip() {
    local zip_path="$1" dest="$2"
    mkdir -p "$dest"
    if command -v unzip >/dev/null 2>&1; then
        unzip -qo "$zip_path" -d "$dest"
    elif command -v bsdtar >/dev/null 2>&1; then
        bsdtar -xf "$zip_path" -C "$dest"
    else
        python3 - "$zip_path" "$dest" <<'PY'
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as zf:
    zf.extractall(sys.argv[2])
PY
    fi
}

zip="Xray-linux-${xray_arch}.zip"
base_url="https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}"
curl -fsSL "${base_url}/${zip}" -o "${tmp}/${zip}"
curl -fsSL "${base_url}/${zip}.dgst" -o "${tmp}/${zip}.dgst"

expected="$(awk -F'= *' '$1 == "SHA2-256" { gsub(/[[:space:]\r]/, "", $2); print $2; exit }' "${tmp}/${zip}.dgst")"
printf '%s  %s\n' "$expected" "${tmp}/${zip}" | sha256sum -c - >/dev/null
extract_zip "${tmp}/${zip}" "${tmp}/xray"

stage="${tmp}/kokoro-xray"
mkdir -p "$stage/prebuilt"
tar -C "$ROOT" \
    --exclude './.git' \
    --exclude './dist' \
    --exclude './prebuilt' \
    -cf - . | tar -C "$stage" -xf -
install -m 755 "${tmp}/xray/xray" "$stage/prebuilt/xray"
install -m 644 "${tmp}/xray/geoip.dat" "${tmp}/xray/geosite.dat" "$stage/prebuilt/"

mkdir -p "$OUT"
asset="kokoro-xray-runtime-linux-${asset_arch}.tar.gz"
tar -C "$tmp" -czf "${OUT}/${asset}" kokoro-xray
(cd "$OUT" && sha256sum "$asset" >"${asset}.sha256")
echo "${OUT}/${asset}"
