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
jq -e '(.outbounds | map(.tag) | index("TOR")) | not' "${OUT}/edge-xray.json" >/dev/null
jq -e '.outbounds | map(.tag) | index("WG_TO_EXIT")' "${OUT}/edge-xray.json" >/dev/null
jq -e '.routing.rules[-1].outboundTag == "WG_TO_EXIT"' "${OUT}/edge-xray.json" >/dev/null
jq -e '.inbounds[] | select(.tag=="REALITY_XHTTP_IN") | .listen == "127.0.0.1"' "${OUT}/edge-xray.json" >/dev/null
jq -e '.inbounds[] | select(.tag=="REALITY_XHTTP_IN") | .streamSettings.xhttpSettings.mode == "auto"' "${OUT}/edge-xray.json" >/dev/null
jq -e '.inbounds[] | select(.tag=="REALITY_XHTTP_IN") | .streamSettings.xhttpSettings.xPaddingObfsMode == null' "${OUT}/edge-xray.json" >/dev/null
jq -e '.inbounds[] | select(.tag=="TLS_XHTTP_IN") | .streamSettings.xhttpSettings.mode == "auto"' "${OUT}/edge-xray.json" >/dev/null
jq -e '.inbounds[] | select(.tag=="TLS_XHTTP_IN") | .streamSettings.xhttpSettings.xPaddingObfsMode == true' "${OUT}/edge-xray.json" >/dev/null
jq -e '.inbounds[] | select(.tag=="TLS_XHTTP_IN") | .streamSettings.xhttpSettings.xPaddingKey == "v"' "${OUT}/edge-xray.json" >/dev/null
jq -e '.inbounds[] | select(.tag=="TLS_XHTTP_IN") | .streamSettings.xhttpSettings.xmux.maxConcurrency == "1-1"' "${OUT}/edge-xray.json" >/dev/null

echo "== edge hy2 xray =="
jq '.inbound.hy2.enabled = true
    | .inbound.hy2.port = 443
    | .inbound.hy2.sni = "hy2.example.com"
    | .paths.hy2_cert = "/tmp/kokoro-test/hy2.crt"
    | .paths.hy2_key = "/tmp/kokoro-test/hy2.key"' \
    "${FIX}/edge-single-config.json" >"${OUT}/edge-hy2-config.json"
jq -n -f "${ROOT}/lib/render.jq" \
    --slurpfile cfg "${OUT}/edge-hy2-config.json" \
    --slurpfile sec "${FIX}/edge-secrets.json" \
    >"${OUT}/edge-hy2-xray.json"
jq -e '.inbounds | map(.tag) | index("HY2_IN")' "${OUT}/edge-hy2-xray.json" >/dev/null
jq -e '.inbounds[] | select(.tag=="HY2_IN") | .listen == "::"' "${OUT}/edge-hy2-xray.json" >/dev/null
jq -e '.inbounds[] | select(.tag=="HY2_IN") | .protocol == "hysteria"' "${OUT}/edge-hy2-xray.json" >/dev/null
jq -e '.inbounds[] | select(.tag=="HY2_IN") | .settings.version == 2' "${OUT}/edge-hy2-xray.json" >/dev/null
jq -e '.inbounds[] | select(.tag=="HY2_IN") | .streamSettings.network == "hysteria"' "${OUT}/edge-hy2-xray.json" >/dev/null
jq -e '.inbounds[] | select(.tag=="HY2_IN") | .streamSettings.security == "tls"' "${OUT}/edge-hy2-xray.json" >/dev/null
jq -e '.inbounds[] | select(.tag=="HY2_IN") | .streamSettings.tlsSettings.alpn[0] == "h3"' "${OUT}/edge-hy2-xray.json" >/dev/null
jq -e '.inbounds[] | select(.tag=="HY2_IN") | .streamSettings.hysteriaSettings.version == 2' "${OUT}/edge-hy2-xray.json" >/dev/null
jq -e '.inbounds[] | select(.tag=="HY2_IN") | .streamSettings.hysteriaSettings.auth == "hy2-test-auth"' "${OUT}/edge-hy2-xray.json" >/dev/null

echo "== edge single-node xray =="
jq -n -f "${ROOT}/lib/render.jq" \
    --slurpfile cfg "${FIX}/edge-single-config.json" \
    --slurpfile sec "${FIX}/edge-secrets.json" \
    >"${OUT}/edge-single-xray.json"
jq -e '(.outbounds | map(.tag) | index("WG_TO_EXIT")) | not' "${OUT}/edge-single-xray.json" >/dev/null
jq -e '.routing.rules[0].domain[0] == "geosite:google"' "${OUT}/edge-single-xray.json" >/dev/null
jq -e '.routing.rules[0].domain | index("domain:googleapis.cn")' "${OUT}/edge-single-xray.json" >/dev/null
jq -e '.routing.rules[0].domain | index("domain:gstatic.cn")' "${OUT}/edge-single-xray.json" >/dev/null
jq -e '.routing.rules | map(select(.domain[]? == "regexp:.*\\.ru$")) | length > 0' "${OUT}/edge-single-xray.json" >/dev/null
jq -e '.routing.rules | map(select(.domain[]? == "regexp:.*\\.su$")) | length > 0' "${OUT}/edge-single-xray.json" >/dev/null
jq -e '.routing.rules | map(select(.ip[]? == "geoip:ru")) | length > 0' "${OUT}/edge-single-xray.json" >/dev/null
jq -e '.routing.rules[-1].outboundTag == "DIRECT"' "${OUT}/edge-single-xray.json" >/dev/null

echo "== edge caddy =="
jq -n -r -f "${ROOT}/lib/caddy.jq" \
    --slurpfile cfg "${FIX}/edge-config.json" \
    --slurpfile sec "${FIX}/edge-secrets.json" \
    >"${OUT}/Caddyfile"
grep -q 'layer4' "${OUT}/Caddyfile"
grep -q 'listener_wrappers' "${OUT}/Caddyfile"
grep -q 'proxy tcp/127.0.0.1:8443' "${OUT}/Caddyfile"

jq '.inbound.tls.ports = [443, 8443]' "${FIX}/edge-config.json" >"${OUT}/edge-ports-config.json"
jq -n -r -f "${ROOT}/lib/caddy.jq" \
    --slurpfile cfg "${OUT}/edge-ports-config.json" \
    --slurpfile sec "${FIX}/edge-secrets.json" \
    >"${OUT}/Caddyfile-ports"
grep -q '^cdn.example.com {' "${OUT}/Caddyfile-ports"
grep -q '^cdn.example.com:8443 {' "${OUT}/Caddyfile-ports"

echo "== exit xray =="
jq -n -f "${ROOT}/lib/render.jq" \
    --slurpfile cfg "${FIX}/exit-config.json" \
    --slurpfile sec "${FIX}/exit-secrets.json" \
    >"${OUT}/exit-xray.json"
jq -e '.inbounds[0].protocol == "wireguard"' "${OUT}/exit-xray.json" >/dev/null
jq -e '.outbounds | map(.tag) | index("TOR")' "${OUT}/exit-xray.json" >/dev/null
jq -e '.routing.rules[0].outboundTag == "TOR"' "${OUT}/exit-xray.json" >/dev/null
jq -e '.routing.rules[-1].outboundTag == "DIRECT"' "${OUT}/exit-xray.json" >/dev/null

if command -v xray >/dev/null 2>&1 && {
    [[ -f "${XRAY_LOCATION_ASSET:-}/geoip.dat" && -f "${XRAY_LOCATION_ASSET:-}/geosite.dat" ]] ||
    [[ -f /usr/local/share/xray/geoip.dat && -f /usr/local/share/xray/geosite.dat ]] ||
    [[ -f /usr/bin/geoip.dat && -f /usr/bin/geosite.dat ]]
}; then
    echo "== xray -test =="
    xray run -test -config "${OUT}/edge-xray.json"
    xray run -test -config "${OUT}/exit-xray.json"
else
    echo "skip xray -test (binary or geodata not installed)"
fi

echo "render-test OK"
