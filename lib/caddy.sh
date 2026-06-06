#!/usr/bin/env bash
# kokoro-xray — Caddy install (apt) and service

source "$(cd -P -- "$(dirname -- "$0")" && pwd -P)/common.sh"

kokoro_caddy_install() {
    kokoro_need_root
    if command -v caddy >/dev/null 2>&1; then
        kokoro_log "caddy already installed"
        return
    fi
    kokoro_pkg_install debian-keyring debian-archive-keyring apt-transport-https gnupg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq caddy
    kokoro_log "caddy installed"
}

kokoro_caddy_restart() {
    kokoro_need_root
    systemctl enable caddy >/dev/null 2>&1 || true
    systemctl restart caddy
}