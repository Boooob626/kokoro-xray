#!/usr/bin/env bash
# kokoro-xray — Caddy with caddy-l4 via xcaddy

source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"
source "${KOKORO_ROOT}/lib/os.sh"

KOKORO_XCADDY_VERSION="${KOKORO_XCADDY_VERSION:-v0.4.6}"
KOKORO_CADDY_L4_VERSION="${KOKORO_CADDY_L4_VERSION:-v0.1.1}"

kokoro_caddy_version() {
    local version
    version="$(kokoro_cfg '.caddy.version')"
    [[ -n "$version" && "$version" != "null" ]] || kokoro_die "missing caddy.version"
    case "$version" in
        v*) printf '%s\n' "$version" ;;
        *) printf 'v%s\n' "$version" ;;
    esac
}

kokoro_caddy_needs_l4() {
    local mode use_l4
    mode="$(kokoro_cfg '.inbound.mode')"
    use_l4="$(kokoro_cfg '.caddy.use_l4')"
    [[ "$use_l4" == "true" && "$mode" == "both" ]]
}

kokoro_caddy_installed_matches() {
    local dest="$1" version="$2" installed
    [[ -x "$dest" ]] || return 1
    installed="$("$dest" version 2>/dev/null | awk '{print $1}')"
    [[ "$installed" == "$version" ]] || return 1
    if kokoro_caddy_needs_l4; then
        "$dest" list-modules 2>/dev/null | grep -q 'layer4' || return 1
    fi
    return 0
}

kokoro_run_with_timer() {
    local label="$1" interval="${KOKORO_BUILD_TIMER_INTERVAL:-30}" pid elapsed status
    shift

    "$@" &
    pid="$!"
    elapsed=0

    while kill -0 "$pid" 2>/dev/null; do
        sleep "$interval"
        if kill -0 "$pid" 2>/dev/null; then
            elapsed=$((elapsed + interval))
            kokoro_log "${label} still running... ${elapsed}s"
        fi
    done

    if wait "$pid"; then
        return 0
    fi
    status=$?
    return "$status"
}

kokoro_caddy_install() {
    local dest caddy_version
    kokoro_need_root
    dest="$(kokoro_cfg '.paths.caddy_bin')"
    caddy_version="$(kokoro_caddy_version)"

    if kokoro_caddy_installed_matches "$dest" "$caddy_version"; then
        kokoro_log "caddy ${caddy_version} already installed"
        kokoro_caddy_install_service
        return
    fi

    kokoro_pkg_install golang-go curl git
    GOBIN=/usr/local/bin go install "github.com/caddyserver/xcaddy/cmd/xcaddy@${KOKORO_XCADDY_VERSION}"

    if kokoro_caddy_needs_l4; then
        kokoro_log "building Caddy ${caddy_version} with caddy-l4 ${KOKORO_CADDY_L4_VERSION}"
        kokoro_log "this can take several minutes on small VPS instances"
        kokoro_run_with_timer "caddy build" xcaddy build "$caddy_version" --with "github.com/mholt/caddy-l4@${KOKORO_CADDY_L4_VERSION}" --output "$dest"
    else
        kokoro_log "building Caddy ${caddy_version}"
        kokoro_log "this can take several minutes on small VPS instances"
        kokoro_run_with_timer "caddy build" xcaddy build "$caddy_version" --output "$dest"
    fi

    chmod 755 "$dest"
    if kokoro_caddy_needs_l4; then
        "$dest" list-modules 2>/dev/null | grep -q 'layer4' || kokoro_die "caddy-l4 module missing after xcaddy build"
    fi
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
