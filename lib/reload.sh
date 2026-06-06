#!/usr/bin/env bash
# kokoro-xray — restart services based on role/mode

source "$(cd -P -- "$(dirname -- "$0")" && pwd -P)/common.sh"

kokoro_reload() {
    kokoro_need_root
    local role mode
    role="$(kokoro_cfg '.role')"
    mode="$(kokoro_cfg '.inbound.mode')"

    systemctl restart xray

    if [[ "$role" == "edge" && ( "$mode" == "tls" || "$mode" == "both" ) ]]; then
        systemctl enable caddy >/dev/null 2>&1 || true
        systemctl restart caddy
    fi

    if [[ "$role" == "exit" && "$(kokoro_cfg '.tor.enabled')" == "true" ]]; then
        systemctl enable tor >/dev/null 2>&1 || true
        systemctl restart tor
    fi
}