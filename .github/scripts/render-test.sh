#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FIX="${ROOT}/.github/fixtures"
OUT="/tmp/kokoro-render-test"
mkdir -p "$OUT"

echo "== edge xray =="
jq -n -f "${ROOT}/lib/render.jq" \
    --slurpfile cfg "${FIX}/edge-config.json" \
    --slurpfile sec "${FIX}/edge-secrets.json" \
    >"${OUT}/edge-xray.json"
jq -e '.inbounds | length == 2' "${OUT}/edge-xray.json" >/dev/null
jq -e '.outbounds | map(.tag) | index("TOR")' "${OUT}/edge-xray.json" >/dev/null
jq -e '.outbounds | map(.tag) | index("WG_TO_EXIT")' "${OUT}/edge-xray.json" >/dev/null
jq -e '.inbounds[] | select(.tag=="REALITY_XHTTP_IN") | .listen == "127.0.0.1"' "${OUT}/edge-xray.json" >/dev/null

echo "== edge caddy =="
jq -n -r -f "${ROOT}/lib/caddy.jq" \
    --slurpfile cfg "${FIX}/edge-config.json" \
    --slurpfile sec "${FIX}/edge-secrets.json" \
    >"${OUT}/Caddyfile"
grep -q 'layer4' "${OUT}/Caddyfile"
grep -q 'proxy 127.0.0.1:8443' "${OUT}/Caddyfile"

echo "== exit xray =="
jq -n -f "${ROOT}/lib/render.jq" \
    --slurpfile cfg "${FIX}/exit-config.json" \
    --slurpfile sec "${FIX}/exit-secrets.json" \
    >"${OUT}/exit-xray.json"
jq -e '.inbounds[0].protocol == "wireguard"' "${OUT}/exit-xray.json" >/dev/null

if command -v xray >/dev/null 2>&1; then
    echo "== xray -test =="
    xray run -test -config "${OUT}/edge-xray.json"
    xray run -test -config "${OUT}/exit-xray.json"
else
    echo "skip xray -test (binary not installed)"
fi

echo "render-test OK"