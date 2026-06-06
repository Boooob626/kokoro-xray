#!/usr/bin/env bash
# kokoro-xray — node health status

source "$(cd -P -- "$(dirname -- "$0")" && pwd -P)/common.sh"

kokoro_health() {
    local role
    role="$(kokoro_cfg '.role')"

    echo "role:     $(kokoro_cfg '.role')"
    echo "mode:     $(kokoro_cfg '.inbound.mode')"
    echo "xray:     $(systemctl is-active xray 2>/dev/null || echo unknown)"

    if [[ "$role" == "edge" ]]; then
        local mode
        mode="$(kokoro_cfg '.inbound.mode')"
        if [[ "$mode" == "tls" || "$mode" == "both" ]]; then
            echo "caddy:    $(systemctl is-active caddy 2>/dev/null || echo unknown)"
        fi
        if [[ "$(kokoro_cfg '.tor.enabled')" == "true" ]]; then
            echo "tor:      $(systemctl is-active tor 2>/dev/null || echo unknown)"
        fi
        if [[ "$(kokoro_cfg '.multinode.enabled')" == "true" ]]; then
            local ip port
            ip="$(kokoro_cfg '.multinode.exit_ip')"
            port="$(kokoro_cfg '.multinode.exit_port')"
            if command -v nc >/dev/null 2>&1; then
                nc -zvu -w 2 "$ip" "$port" 2>/dev/null && echo "exit wg:  udp ${ip}:${port} reachable" \
                    || echo "exit wg:  udp ${ip}:${port} NOT reachable"
            else
                echo "exit wg:  check UDP ${ip}:${port} manually"
            fi
        fi
    fi

    if [[ "$role" == "exit" ]]; then
        echo "wg port:  $(kokoro_cfg '.multinode.exit_port')/udp"
    fi
}