#!/usr/bin/env bash
# kokoro-xray — TCP Fast Open + BBR (fq qdisc) QoL tuning

: "${KOKORO_ROOT:=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)}"
source "${KOKORO_ROOT}/lib/common.sh"

: "${KOKORO_SYSCTL_NET:=/etc/sysctl.d/99-kokoro-network.conf}"
: "${KOKORO_MOD_BBR:=/etc/modules-load.d/kokoro-bbr.conf}"

kokoro_network_sysctl() {
    sysctl -n "$1" 2>/dev/null || echo ""
}

kokoro_network_cc_list() {
    kokoro_network_sysctl net.ipv4.tcp_available_congestion_control
}

kokoro_network_cc_prefer() {
    local avail="$1"
    if echo "$avail" | grep -qw bbr2; then
        echo "bbr2"
    elif echo "$avail" | grep -qw bbr; then
        echo "bbr"
    fi
}

kokoro_network_cc_ensure() {
    local avail pref
    avail="$(kokoro_network_cc_list)"
    pref="$(kokoro_network_cc_prefer "$avail")"
    [[ -n "$pref" ]] && { echo "$pref"; return 0; }

    modprobe tcp_bbr2 2>/dev/null || true
    modprobe tcp_bbr 2>/dev/null || true
    avail="$(kokoro_network_cc_list)"
    pref="$(kokoro_network_cc_prefer "$avail")"
    [[ -n "$pref" ]] && { echo "$pref"; return 0; }
    return 1
}

kokoro_network_tfo_want() { echo 3; }

kokoro_network_qdisc_want() { echo "fq"; }

kokoro_network_rmem_want() { echo 134217728; }

kokoro_network_wmem_want() { echo 134217728; }

kokoro_network_apply_sysctl() {
    local key="$1" value="$2" path="/proc/sys/${1//./\/}"
    [[ -e "$path" ]] || return 0
    sysctl -w "${key}=${value}" >/dev/null 2>&1 || kokoro_warn "sysctl failed: ${key}=${value}"
}

kokoro_network_status_line() {
    local name current want ok
    name="$1"
    current="$2"
    want="$3"
    if [[ "$current" == "$want" ]]; then
        ok="yes"
    else
        ok="no"
    fi
    printf '  %-14s current=%-12s want=%-8s ok=%s\n' "$name" "${current:-?}" "$want" "$ok"
}

kokoro_network_tune_check() {
    local tfo4 tfo6 cc qdisc want_cc
    tfo4="$(kokoro_network_sysctl net.ipv4.tcp_fastopen)"
    tfo6="$(kokoro_network_sysctl net.ipv6.tcp_fastopen)"
    cc="$(kokoro_network_sysctl net.ipv4.tcp_congestion_control)"
    qdisc="$(kokoro_network_sysctl net.core.default_qdisc)"
    want_cc="$(kokoro_network_cc_prefer "$(kokoro_network_cc_list)")"
    [[ -n "$want_cc" ]] || want_cc="bbr"

    echo "network tuning:"
    kokoro_network_status_line "tcp_fastopen4" "$tfo4" "$(kokoro_network_tfo_want)"
    if [[ -f /proc/sys/net/ipv6/tcp_fastopen ]]; then
        kokoro_network_status_line "tcp_fastopen6" "$tfo6" "$(kokoro_network_tfo_want)"
    fi
    kokoro_network_status_line "congestion_ctl" "$cc" "$want_cc"
    kokoro_network_status_line "default_qdisc" "$qdisc" "$(kokoro_network_qdisc_want)"
    kokoro_network_status_line "rmem_max" "$(kokoro_network_sysctl net.core.rmem_max)" "$(kokoro_network_rmem_want)"
    kokoro_network_status_line "wmem_max" "$(kokoro_network_sysctl net.core.wmem_max)" "$(kokoro_network_wmem_want)"
    echo "  available_cc   $(kokoro_network_cc_list)"

    if [[ "$tfo4" == "$(kokoro_network_tfo_want)" \
        && "$cc" == "$want_cc" \
        && "$qdisc" == "$(kokoro_network_qdisc_want)" \
        && "$(kokoro_network_sysctl net.core.rmem_max)" == "$(kokoro_network_rmem_want)" \
        && "$(kokoro_network_sysctl net.core.wmem_max)" == "$(kokoro_network_wmem_want)" ]]; then
        return 0
    fi
    return 1
}

kokoro_network_tune_write() {
    local cc="$1"
    install -d -m 755 /etc/sysctl.d /etc/modules-load.d

    cat >"${KOKORO_MOD_BBR}" <<'EOF'
# kokoro-xray — load BBR congestion control (bbr2 if kernel supports it)
tcp_bbr2
tcp_bbr
EOF

    cat >"${KOKORO_SYSCTL_NET}" <<EOF
# kokoro-xray — TCP Fast Open + BBR (fq qdisc)
# https://github.com/google/bbr

net.ipv4.tcp_fastopen = $(kokoro_network_tfo_want)
net.ipv6.tcp_fastopen = $(kokoro_network_tfo_want)
net.core.default_qdisc = $(kokoro_network_qdisc_want)
net.core.rmem_max = $(kokoro_network_rmem_want)
net.core.wmem_max = $(kokoro_network_wmem_want)
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192
net.ipv4.tcp_congestion_control = ${cc}
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
EOF
}

kokoro_network_tune_apply() {
    local cc
    kokoro_need_root

    cc="$(kokoro_network_cc_ensure)" || {
        kokoro_warn "BBR not available (kernel module tcp_bbr missing?)"
        return 1
    }

    kokoro_network_tune_write "$cc"
    modprobe tcp_bbr2 2>/dev/null || true
    modprobe tcp_bbr 2>/dev/null || true

    kokoro_network_apply_sysctl net.ipv4.tcp_fastopen "$(kokoro_network_tfo_want)"
    kokoro_network_apply_sysctl net.ipv6.tcp_fastopen "$(kokoro_network_tfo_want)"
    kokoro_network_apply_sysctl net.core.default_qdisc "$(kokoro_network_qdisc_want)"
    kokoro_network_apply_sysctl net.core.rmem_max "$(kokoro_network_rmem_want)"
    kokoro_network_apply_sysctl net.core.wmem_max "$(kokoro_network_wmem_want)"
    kokoro_network_apply_sysctl net.core.rmem_default 262144
    kokoro_network_apply_sysctl net.core.wmem_default 262144
    kokoro_network_apply_sysctl net.ipv4.udp_rmem_min 8192
    kokoro_network_apply_sysctl net.ipv4.udp_wmem_min 8192
    kokoro_network_apply_sysctl net.ipv4.tcp_congestion_control "${cc}"
    kokoro_network_apply_sysctl net.ipv4.tcp_slow_start_after_idle 0
    kokoro_network_apply_sysctl net.ipv4.tcp_mtu_probing 1

    kokoro_log "network tuned: TFO=$(kokoro_network_tfo_want) cc=${cc} qdisc=$(kokoro_network_qdisc_want) udp-buf=$(kokoro_network_rmem_want)"
    kokoro_log "persisted: ${KOKORO_SYSCTL_NET}"
}

kokoro_network_tune() {
    local check_only=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --check) check_only=true; shift ;;
            -h|--help)
                cat <<'EOF'
kokoro-xray tune — enable TCP Fast Open + BBR

Checks and applies (persisted in /etc/sysctl.d/):
  net.ipv4.tcp_fastopen=3
  net.ipv6.tcp_fastopen=3
  net.core.default_qdisc=fq
  net.core.rmem_max=134217728
  net.core.wmem_max=134217728
  net.ipv4.tcp_congestion_control=bbr2|bbr (best available)
  net.ipv4.tcp_slow_start_after_idle=0

Usage:
  kokoro-xray tune
  kokoro-xray tune --check
EOF
                return 0
                ;;
            *) kokoro_die "unknown option: $1 (try --help)" ;;
        esac
    done

    if kokoro_network_tune_check; then
        kokoro_log "network tuning already optimal"
        return 0
    fi

    if [[ "$check_only" == "true" ]]; then
        kokoro_warn "network tuning can be improved — run: kokoro-xray tune"
        return 1
    fi

    if ! kokoro_network_tune_apply; then
        return 1
    fi
    kokoro_network_tune_check || true
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    kokoro_network_tune "$@"
fi
