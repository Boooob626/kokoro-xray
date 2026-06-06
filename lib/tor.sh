#!/usr/bin/env bash
# kokoro-xray — Tor SOCKS for .onion routing

source "$(cd -P -- "$(dirname -- "$0")" && pwd -P)/common.sh"

kokoro_tor_install() {
    kokoro_need_root
    kokoro_pkg_install tor
    systemctl enable tor >/dev/null 2>&1 || true
    systemctl restart tor
    kokoro_log "tor installed (socks 127.0.0.1:9050)"
}

kokoro_tor_enable() {
    kokoro_tor_install
    kokoro_cfg_set '.tor.enabled' 'true'
}

kokoro_tor_disable() {
    kokoro_cfg_set '.tor.enabled' 'false'
}