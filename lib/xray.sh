#!/usr/bin/env bash
# kokoro-xray — Xray-core install and service

source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"

KOKORO_XRAY_VERSION="${KOKORO_XRAY_VERSION:-v26.6.1}"

kokoro_xray_release_arch() {
    case "$(uname -m)" in
        x86_64) printf '64\n' ;;
        aarch64) printf 'arm64-v8a\n' ;;
        *) kokoro_die "unsupported arch: $(uname -m)" ;;
    esac
}

kokoro_xray_release_zip() {
    printf 'Xray-linux-%s.zip\n' "$(kokoro_xray_release_arch)"
}

kokoro_xray_verify_zip() {
    local zip_path="$1" dgst_path="$2" expected
    expected="$(awk -F'= *' '$1 == "SHA2-256" { gsub(/[[:space:]\r]/, "", $2); print $2; exit }' "$dgst_path")"
    [[ -n "$expected" ]] || kokoro_die "SHA2-256 not found in $(basename "$dgst_path")"
    printf '%s  %s\n' "$expected" "$zip_path" | sha256sum -c - >/dev/null
}

kokoro_xray_download_release_zip() {
    local tmp="$1" zip base_url
    zip="$(kokoro_xray_release_zip)"
    base_url="https://github.com/XTLS/Xray-core/releases/download/${KOKORO_XRAY_VERSION}"
    curl -fsSL "${base_url}/${zip}" -o "${tmp}/${zip}"
    curl -fsSL "${base_url}/${zip}.dgst" -o "${tmp}/${zip}.dgst"
    kokoro_xray_verify_zip "${tmp}/${zip}" "${tmp}/${zip}.dgst"
    printf '%s\n' "$zip"
}

kokoro_xray_load_paths() {
    dest="$(kokoro_cfg '.paths.xray_bin')"
    geo_dir="$(kokoro_cfg '.paths.geo_dir')"
    xray_config="$(kokoro_cfg '.paths.xray_config')"

    [[ -n "$dest" && "$dest" != "null" ]] || kokoro_die "missing required config path: .paths.xray_bin"
    [[ -n "$geo_dir" && "$geo_dir" != "null" ]] || kokoro_die "missing required config path: .paths.geo_dir"
    [[ -n "$xray_config" && "$xray_config" != "null" ]] || kokoro_die "missing required config path: .paths.xray_config"
}

kokoro_xray_install() {
    local zip dest geo_dir xray_config tmp
    kokoro_need_root
    kokoro_xray_load_paths
    tmp="$(mktemp -d)"
    zip="$(kokoro_xray_download_release_zip "$tmp")"
    unzip -qo "${tmp}/${zip}" -d "$tmp"
    install -m 755 "${tmp}/xray" "$dest"
    install -d "$geo_dir"
    install -m 644 "${tmp}/geoip.dat" "${tmp}/geosite.dat" "$geo_dir/"
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
