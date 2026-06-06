#!/usr/bin/env bash
# kokoro-xray — Caddy with caddy-l4 via xcaddy

source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"
source "${KOKORO_ROOT}/lib/os.sh"

kokoro_caddy_install() {
    local dest mode use_l4
    kokoro_need_root
    dest="$(kokoro_cfg '.paths.caddy_bin')"
    mode="$(kokoro_cfg '.inbound.mode')"
    use_l4="$(kokoro_cfg '.caddy.use_l4')"

    if [[ -x "$dest" ]] && "$dest" list-modules 2>/dev/null | grep -q 'layer4'; then
        kokoro_log "caddy with layer4 already installed"
        kokoro_caddy_install_service
        return
    fi

    kokoro_pkg_install golang-go curl git
    command -v xcaddy >/dev/null 2>&1 || {
        GOBIN=/usr/local/bin go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
    }

    if [[ "$use_l4" == "true" && ( "$mode" == "both" || "$mode" == "tls" ) ]]; then
        xcaddy build --with github.com/mholt/caddy-l4 --output "$dest"
    else
        xcaddy build --output "$dest"
    fi

    chmod 755 "$dest"
    if [[ "$use_l4" == "true" && ( "$mode" == "both" ) ]]; then
        "$dest" list-modules 2>/dev/null | grep -q 'layer4' || kokoro_die "caddy-l4 module missing after xcaddy build"
    fi
    kokoro_log "caddy installed to ${dest}"
    kokoro_caddy_install_service
}

kokoro_caddy_install_service() {
    local caddy_bin caddyfile
    caddy_bin="$(kokoro_cfg '.paths.caddy_bin')"
    caddyfile="$(kokoro_cfg '.paths.caddyfile')"
    install -d "$(dirname "$caddyfile")"
    cat >/etc/systemd/system/caddy.service <<EOF
[Unit]
Description=Caddy Service (kokoro-xray)
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
ExecStart=${caddy_bin} run --environ --config ${caddyfile}
ExecReload=${caddy_bin} reload --config ${caddyfile} --force
TimeoutStopSec=5s
LimitNOFILE=1048576
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable caddy >/dev/null 2>&1 || true
}
