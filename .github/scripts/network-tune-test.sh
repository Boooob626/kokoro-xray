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
    grep -q 'rmem_max = 134217728' "${KOKORO_SYSCTL_NET}"
    grep -q 'wmem_max = 134217728' "${KOKORO_SYSCTL_NET}"
    grep -q 'udp_rmem_min = 8192' "${KOKORO_SYSCTL_NET}"
    grep -q 'tcp_mtu_probing = 1' "${KOKORO_SYSCTL_NET}"
    grep -q 'tcp_slow_start_after_idle = 0' "${KOKORO_SYSCTL_NET}"
    grep -q 'tcp_bbr' "${KOKORO_MOD_BBR}"
    rm -rf "$tmp"
    echo "sysctl_write OK"
}

test_tune_cli_args() {
    local tmp out err
    tmp="$(mktemp -d)"
    out="$(HOME="$tmp" bash "${ROOT}/kokoro-xray.sh" tune --help)"
    printf '%s\n' "$out" | grep -q 'kokoro-xray tune --check'

    if HOME="$tmp" bash "${ROOT}/kokoro-xray.sh" tune --bad-option >"${tmp}/out" 2>"${tmp}/err"; then
        echo "bad tune option should fail"; exit 1
    fi
    err="$(cat "${tmp}/err")"
    printf '%s\n' "$err" | grep -q 'unknown option: --bad-option'
    rm -rf "$tmp"
    echo "tune_cli_args OK"
}

test_cc_prefer
test_sysctl_write
test_tune_cli_args
echo "network-tune-test OK"
