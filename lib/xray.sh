#!/usr/bin/env bash
# kokoro-xray — Xray-core install and service

source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"
source "${KOKORO_ROOT}/lib/geodata.sh"

KOKORO_XRAY_VERSION="${KOKORO_XRAY_VERSION:-v26.6.1}"

kokoro_xray_required_path() {
    local key value
    key="$1"
    value="$(kokoro_cfg "$key")"
    [[ -n "$value" && "$value" != "null" ]] || kokoro_die "missing required config path: $key"
    printf '%s\n' "$value"
}

kokoro_xray_install() {
    local arch zip url dest tmp
    kokoro_need_root
    dest="$(kokoro_xray_required_path '.paths.xray_bin')"
    arch="$(uname -m)"
    case "$arch" in
        x86_64) arch="64" ;;
        aarch64) arch="arm64-v8a" ;;
        *) kokoro_die "unsupported arch: $arch" ;;
    esac
    zip="Xray-linux-${arch}.zip"
    url="https://github.com/XTLS/Xray-core/releases/download/${KOKORO_XRAY_VERSION}/${zip}"
    tmp="$(mktemp -d)"
    curl -fsSL "$url" -o "${tmp}/${zip}"
    unzip -qo "${tmp}/${zip}" -d "$tmp"
    install -m 755 "${tmp}/xray" "$dest"
    install -d "$(kokoro_xray_required_path '.paths.geo_dir')"
    install -m 644 "${tmp}/geoip.dat" "${tmp}/geosite.dat" "$(kokoro_xray_required_path '.paths.geo_dir')/"
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
Description=Xray Service (kokoro-xray)
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
