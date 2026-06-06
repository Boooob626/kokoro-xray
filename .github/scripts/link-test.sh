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
SCRIPT

rm -rf "$tmp_home"
echo "link-test OK"
