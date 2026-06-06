#!/usr/bin/env bash
# kokoro-xray — validate intent before render

source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"
source "${KOKORO_ROOT}/lib/firewall.sh"

kokoro_preflight() {
    local role mode
    role="$(kokoro_cfg '.role')"
    mode="$(kokoro_cfg '.inbound.mode')"

    kokoro_preflight_paths
    [[ -n "$role" && "$role" != "null" ]] || kokoro_die "role not set (edge or exit)"

    case "$role" in
        edge) kokoro_preflight_edge "$mode" ;;
        exit) kokoro_preflight_exit ;;
        *) kokoro_die "unknown role: $role" ;;
    esac

    if [[ "$(kokoro_cfg '.firewall.enabled // false')" == "true" ]]; then
        kokoro_firewall_validate_extra
    fi

    kokoro_check_secret_perms
}

kokoro_preflight_paths() {
    local key value
    for key in \
        '.paths.xray_config' \
        '.paths.xray_bin' \
        '.paths.geo_dir'; do
        value="$(kokoro_cfg "$key")"
        [[ -n "$value" && "$value" != "null" ]] || kokoro_die "missing required config path: $key"
    done
}

kokoro_preflight_port() {
    local value="$1" name="$2"
    [[ "$value" =~ ^[0-9]+$ && "$value" -ge 1 && "$value" -le 65535 ]] || kokoro_die "invalid port for $name: $value"
}

kokoro_preflight_edge() {
    local mode="$1" cdn xhttp_socket socket_path fallback_type fallback_root fallback_proxy
    case "$mode" in
        reality|tls|both) ;;
        *) kokoro_die "invalid inbound.mode: $mode" ;;
    esac

    [[ -n "$(kokoro_sec '.inbound.uuid')" ]] || kokoro_die "missing inbound.uuid in secrets.json"
    [[ -n "$(kokoro_sec '.inbound.xhttp_path')" ]] || kokoro_die "missing inbound.xhttp_path in secrets.json"

    if [[ "$mode" == "reality" || "$mode" == "both" ]]; then
        [[ -n "$(kokoro_sec '.inbound.reality.private_key')" ]] || kokoro_die "missing reality private key"
        [[ -n "$(kokoro_sec '.inbound.reality.short_ids[0]')" ]] || kokoro_die "missing reality short_id"
    fi

    if [[ "$mode" == "tls" || "$mode" == "both" ]]; then
        cdn="$(kokoro_cfg '.inbound.tls.cdn_domain')"
        [[ -n "$cdn" && "$cdn" != "null" ]] || kokoro_die "inbound.tls.cdn_domain required for tls/both mode"

        xhttp_socket="$(kokoro_cfg '.inbound.xhttp.socket // true')"
        socket_path="$(kokoro_cfg '.inbound.xhttp.socket_path // ""')"
        if [[ "$xhttp_socket" == "true" ]]; then
            [[ "$socket_path" == /* ]] || kokoro_die "inbound.xhttp.socket_path must be absolute"
        fi

        fallback_type="$(kokoro_cfg '.fallback.type // "static"')"
        case "$fallback_type" in
            static)
                fallback_root="$(kokoro_cfg '.fallback.root // ""')"
                [[ "$fallback_root" == /* ]] || kokoro_die "fallback.root must be absolute"
                ;;
            proxy)
                fallback_proxy="$(kokoro_cfg '.fallback.proxy_url // ""')"
                [[ "$fallback_proxy" =~ ^https?://[^[:space:]]+$ ]] || kokoro_die "fallback.proxy_url must be http(s) URL"
                ;;
            none) ;;
            *) kokoro_die "invalid fallback.type: $fallback_type" ;;
        esac
    fi

    if [[ "$(kokoro_cfg '.tor.enabled')" == "true" ]]; then
        kokoro_die "Tor is exit-only — enable on exit node after pair (kokoro-xray tor on)"
    fi

    if [[ "$(kokoro_cfg '.multinode.enabled')" == "true" ]]; then
        [[ -n "$(kokoro_sec '.multinode.edge_wg_privkey')" ]] || kokoro_die "missing edge WG private key"
        [[ -n "$(kokoro_cfg '.multinode.peer_exit_pubkey')" ]] || kokoro_die "missing multinode.peer_exit_pubkey"
        [[ -n "$(kokoro_cfg '.multinode.exit_ip')" ]] || kokoro_die "missing multinode.exit_ip"
        kokoro_preflight_port "$(kokoro_cfg '.multinode.exit_port')" "multinode.exit_port"
    fi
}

kokoro_preflight_exit() {
    [[ -n "$(kokoro_sec '.multinode.exit_wg_privkey')" ]] || kokoro_die "missing exit WG private key"
    [[ -n "$(kokoro_cfg '.multinode.peer_edge_pubkey')" ]] || kokoro_die "missing multinode.peer_edge_pubkey (run pair)"
    kokoro_preflight_port "$(kokoro_cfg '.multinode.exit_port')" "multinode.exit_port"

    if [[ "$(kokoro_cfg '.tor.enabled')" == "true" ]]; then
        [[ -n "$(kokoro_cfg '.multinode.peer_edge_pubkey')" ]] || kokoro_die "pair edge before enabling Tor"
    fi
}
