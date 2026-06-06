#!/usr/bin/env bash
# kokoro-xray — geodata install and update

source "$(cd -P -- "$(dirname -- "$0")" && pwd -P)/common.sh"

KOKORO_XRAY_VERSION="${KOKORO_XRAY_VERSION:-v26.6.1}"

kokoro_geodata_install() {
    local geo_dir arch zip url tmp
    geo_dir="$(kokoro_cfg '.paths.geo_dir')"
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
    install -d "$geo_dir"
    install -m 644 "${tmp}/geoip.dat" "${tmp}/geosite.dat" "$geo_dir/"
    rm -rf "$tmp"
    kokoro_log "geodata installed to ${geo_dir}"
}

kokoro_geodata_update() {
    kokoro_need_root
    kokoro_geodata_install
}