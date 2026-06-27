#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export KOKORO_ROOT="$ROOT"
source "${ROOT}/lib/firewall.sh"

test_ssh_detect() {
    local tmp port
    tmp="$(mktemp)"
    cat >"$tmp" <<'EOF'
# comment
Port 2222
Port 3333
EOF
    KOKORO_SSHD_CONFIG="$tmp"
    port="$(kokoro_firewall_detect_ssh)"
    [[ "$port" == "3333" ]]
    rm -f "$tmp"
    echo "ssh_detect OK"
}

test_parse_allow() {
    [[ "$(kokoro_firewall_parse_allow '5555')" == "5555" ]]
    [[ "$(kokoro_firewall_parse_allow '5000-5010')" == "5000:5010" ]]
    [[ "$(kokoro_firewall_parse_allow '9000/udp')" == "9000/udp" ]]
    [[ "$(kokoro_firewall_parse_allow '5000:5010/tcp')" == "5000:5010/tcp" ]]
    if ( kokoro_firewall_parse_allow '99999' ) >/dev/null 2>&1; then
        echo "invalid port should fail"; exit 1
    fi
    if ( kokoro_firewall_parse_allow '100-50' ) >/dev/null 2>&1; then
        echo "invalid range should fail"; exit 1
    fi
    echo "parse_allow OK"
}

test_firewall_cli() {
    local tmp out
    tmp="$(mktemp -d)"
    out="$(HOME="$tmp" bash "${ROOT}/kokoro-xray.sh" firewall status)"
    printf '%s\n' "$out" | grep -q 'firewall.enabled:'
    rm -rf "$tmp"
    echo "firewall_cli OK"
}

test_ssh_detect
test_parse_allow
test_firewall_cli
echo "firewall-test OK"
