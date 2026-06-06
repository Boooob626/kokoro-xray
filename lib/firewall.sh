#!/usr/bin/env bash
# kokoro-xray — firewall rules (ufw or print iptables)

source "$(cd -P -- "$(dirname -- "$0")" && pwd -P)/common.sh"

kokoro_firewall_apply() {
    local role mode port
    role="$(kokoro_cfg '.role')"
    mode="$(kokoro_cfg '.inbound.mode')"
    port="$(kokoro_cfg '.multinode.exit_port')"

    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
        case "$role" in
            edge)
                ufw allow 443/tcp comment 'kokoro-xray' >/dev/null 2>&1 || true
                ufw allow 80/tcp comment 'kokoro-acme' >/dev/null 2>&1 || true
                ;;
            exit)
                ufw allow "${port}/udp" comment 'kokoro-wg' >/dev/null 2>&1 || true
                ;;
        esac
        return
    fi

    case "$role" in
        edge)
            if [[ "$mode" == "tls" || "$mode" == "both" || "$mode" == "reality" ]]; then
                kokoro_warn "ensure firewall allows: 443/tcp, 80/tcp"
            fi
            ;;
        exit)
            kokoro_warn "ensure firewall allows: ${port}/udp"
            ;;
    esac
}