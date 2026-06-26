#!/usr/bin/env bash
# kokoro-xray — official Caddy release install

source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"
source "${KOKORO_ROOT}/lib/os.sh"

KOKORO_CADDY_VERSION="${KOKORO_CADDY_VERSION:-v2.9.1}"

kokoro_caddy_release_arch() {
    case "$(uname -m)" in
        x86_64 | amd64) echo "amd64" ;;
        aarch64 | arm64) echo "arm64" ;;
        *) kokoro_die "unsupported Caddy architecture: $(uname -m)" ;;
    esac
}

kokoro_caddy_installed_matches() {
    local dest="$1" version="$2" installed
    [[ -x "$dest" ]] || return 1
    installed="$("$dest" version 2>/dev/null | awk '{print $1}')"
    [[ "$installed" == "$version" ]]
}

kokoro_caddy_install() {
    local dest caddy_version plain_version arch asset base_url tmp expected
    kokoro_need_root
    dest="$(kokoro_cfg '.paths.caddy_bin')"
    caddy_version="$KOKORO_CADDY_VERSION"

    if kokoro_caddy_installed_matches "$dest" "$caddy_version"; then
        kokoro_log "caddy ${caddy_version} already installed"
        kokoro_caddy_install_service
        return
    fi

    plain_version="${caddy_version#v}"
    arch="$(kokoro_caddy_release_arch)"
    asset="caddy_${plain_version}_linux_${arch}.tar.gz"
    base_url="https://github.com/caddyserver/caddy/releases/download/${caddy_version}"
    tmp="$(mktemp -d)"

    if ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1 || ! command -v sha512sum >/dev/null 2>&1; then
        kokoro_pkg_install curl ca-certificates tar coreutils
    fi

    kokoro_log "downloading official Caddy ${caddy_version} (${arch})"
    curl -fsSL "${base_url}/${asset}" -o "${tmp}/${asset}" || { rm -rf "$tmp"; kokoro_die "failed to download Caddy ${caddy_version}"; }
    curl -fsSL "${base_url}/caddy_${plain_version}_checksums.txt" -o "${tmp}/checksums.txt" || { rm -rf "$tmp"; kokoro_die "failed to download Caddy checksums"; }
    expected="$(awk -v f="$asset" '$2 == f { print $1; exit }' "${tmp}/checksums.txt")"
    [[ -n "$expected" ]] || { rm -rf "$tmp"; kokoro_die "Caddy checksum missing for ${asset}"; }
    printf '%s  %s\n' "$expected" "${tmp}/${asset}" | sha512sum -c - >/dev/null || { rm -rf "$tmp"; kokoro_die "Caddy checksum failed"; }

    tar -xzf "${tmp}/${asset}" -C "$tmp" caddy || { rm -rf "$tmp"; kokoro_die "failed to extract Caddy"; }
    install -m 755 "${tmp}/caddy" "$dest"
    rm -rf "$tmp"
    kokoro_log "caddy ${caddy_version} installed to ${dest}"
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
