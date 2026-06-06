#!/usr/bin/env bash
# kokoro-xray — Xray-core install and service

source "$(cd -P -- "$(dirname -- "$0")" && pwd -P)/common.sh"

KOKORO_XRAY_VERSION="${KOKORO_XRAY_VERSION:-v26.6.1}"

kokoro_xray_install() {
    local arch zip url dest
    kokoro_need_root
    dest="$(kokoro_cfg '.paths.xray_bin')"
    arch="$(uname -m)"
    case "$arch" in
        x86_64) arch="64" ;;
        aarch64) arch="arm64-v8a" ;;
        *) kokoro_die "unsupported arch: $arch" ;;
    esac
    zip="Xray-linux-${arch}.zip"
    url="https://github.com/XTLS/Xray-core/releases/download/${KOKORO_XRAY_VERSION}/${zip}"
    local tmp
    tmp="$(mktemp -d)"
    curl -fsSL "$url" -o "${tmp}/${zip}"
    unzip -qo "${tmp}/${zip}" -d "$tmp"
    install -m 755 "${tmp}/xray" "$dest"
    install -d /usr/local/share/xray
    install -m 644 "${tmp}/geoip.dat" "${tmp}/geosite.dat" /usr/local/share/xray/ 2>/dev/null || true
    rm -rf "$tmp"
    kokoro_xray_install_service
    kokoro_log "xray ${KOKORO_XRAY_VERSION} installed"
}

kokoro_xray_install_service() {
    local cfg
    cfg="$(kokoro_cfg '.paths.xray_config')"
    install -d "$(dirname "$cfg")"
    cat >/etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
Type=simple
ExecStart=$(kokoro_cfg '.paths.xray_bin') run -config ${cfg}
Restart=on-failure
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable xray >/dev/null 2>&1 || true
}

kokoro_xray_restart() {
    kokoro_need_root
    systemctl restart xray
}