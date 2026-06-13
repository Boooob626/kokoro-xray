#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FIX="${ROOT}/.github/fixtures"
tmp_home="$(mktemp -d)"
install -d -m 700 "${tmp_home}/.kokoro-xray"
cp "${FIX}/edge-config.json" "${tmp_home}/.kokoro-xray/config.json"
cp "${FIX}/edge-secrets.json" "${tmp_home}/.kokoro-xray/secrets.json"

HOME="$tmp_home" KOKORO_ROOT="$ROOT" bash <<'SCRIPT'
set -euo pipefail
source "${KOKORO_ROOT}/lib/link.sh"

expected_pbk="$(kokoro_sec '.inbound.reality.public_key')"
reality="$(kokoro_link_reality_url | tr -d '\n')"
[[ "$reality" == vless://* ]]
[[ "$reality" == *"security=reality"* ]]
[[ "$reality" == *"type=xhttp"* ]]
[[ "$reality" == *"pbk=${expected_pbk}"* ]]

tls="$(kokoro_link_tls_url | tr -d '\n')"
[[ "$tls" == vless://* ]]
[[ "$tls" == *"security=tls"* ]]
[[ "$tls" == *"cdn.example.com"* ]]
[[ "$tls" == *"host=cdn.example.com"* ]]
[[ "$tls" == *"sni=cdn.example.com"* ]]
[[ "$tls" == *"fp=chrome"* ]]
[[ "$tls" == *"alpn=h2"* ]]

tls_json="$(kokoro_link_tls_json)"
printf '%s\n' "$tls_json" | jq -e '.outbounds[0].tag == "kokoro-tls"' >/dev/null
printf '%s\n' "$tls_json" | jq -e '.outbounds[0].streamSettings.security == "tls"' >/dev/null
printf '%s\n' "$tls_json" | jq -e '.outbounds[0].streamSettings.tlsSettings.serverName == "cdn.example.com"' >/dev/null
printf '%s\n' "$tls_json" | jq -e '.outbounds[0].streamSettings.tlsSettings.fingerprint == "chrome"' >/dev/null
printf '%s\n' "$tls_json" | jq -e '.outbounds[0].streamSettings.tlsSettings.alpn[0] == "h2"' >/dev/null
printf '%s\n' "$tls_json" | jq -e '.outbounds[0].streamSettings.xhttpSettings.mode == "auto"' >/dev/null
printf '%s\n' "$tls_json" | jq -e '.outbounds[0].streamSettings.xhttpSettings.xPaddingObfsMode == true' >/dev/null
printf '%s\n' "$tls_json" | jq -e '.outbounds[0].streamSettings.xhttpSettings.xmux.maxConcurrency == "1-1"' >/dev/null

cli_tls_json="$(kokoro_link_show --json tls)"
printf '%s\n' "$cli_tls_json" | jq -e '.outbounds[0].tag == "kokoro-tls"' >/dev/null

if command -v xray >/dev/null 2>&1; then
    printf '%s\n' "$cli_tls_json" >"${HOME}/.kokoro-xray/client-tls.json"
    xray run -test -config "${HOME}/.kokoro-xray/client-tls.json"
fi
SCRIPT

rm -rf "$tmp_home"
echo "link-test OK"
