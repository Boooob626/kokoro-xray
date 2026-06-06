#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export KOKORO_ROOT="$ROOT"
source "${ROOT}/lib/network-tune.sh"

test_cc_prefer() {
    [[ "$(kokoro_network_cc_prefer 'reno cubic bbr')" == "bbr" ]]
    [[ "$(kokoro_network_cc_prefer 'reno cubic bbr2 bbr')" == "bbr2" ]]
    [[ -z "$(kokoro_network_cc_prefer 'reno cubic')" ]]
    echo "cc_prefer OK"
}

test_sysctl_write() {
    local tmp cc
    tmp="$(mktemp -d)"
    KOKORO_SYSCTL_NET="${tmp}/99-kokoro-network.conf"
    KOKORO_MOD_BBR="${tmp}/kokoro-bbr.conf"

    kokoro_network_tune_write "bbr"
    grep -q 'tcp_fastopen = 3' "${KOKORO_SYSCTL_NET}"
    grep -q 'tcp_congestion_control = bbr' "${KOKORO_SYSCTL_NET}"
    grep -q 'default_qdisc = fq' "${KOKORO_SYSCTL_NET}"
    grep -q 'tcp_slow_start_after_idle = 0' "${KOKORO_SYSCTL_NET}"
    grep -q 'tcp_bbr' "${KOKORO_MOD_BBR}"
    rm -rf "$tmp"
    echo "sysctl_write OK"
}

test_cc_prefer
test_sysctl_write
echo "network-tune-test OK"