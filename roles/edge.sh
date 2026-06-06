#!/usr/bin/env bash
# kokoro-xray — edge node (DE) setup

source "$(cd -P -- "$(dirname -- "$0")/../lib" && pwd -P)/common.sh"
source "$(kokoro_project_root)/lib/os.sh"
source "$(kokoro_project_root)/lib/xray.sh"
source "$(kokoro_project_root)/lib/caddy.sh"
source "$(kokoro_project_root)/lib/keys.sh"
source "$(kokoro_project_root)/lib/render.sh"
source "$(kokoro_project_root)/lib/validate.sh"
source "$(kokoro_project_root)/lib/tor.sh"

kokoro_edge_install() {
    kokoro_need_root
    kokoro_ensure_config
    kokoro_cfg_set_str '.role' 'edge'

    kokoro_install_deps
    kokoro_xray_install

    local mode
    mode="$(kokoro_cfg '.inbound.mode')"
    if [[ "$mode" == "tls" || "$mode" == "both" ]]; then
        kokoro_caddy_install
    fi

    kokoro_gen_edge_secrets
    kokoro_build_edge_xray

    if [[ "$mode" == "tls" || "$mode" == "both" ]]; then
        kokoro_build_edge_caddy
        kokoro_caddy_restart
    fi

    if [[ "$(kokoro_cfg '.tor.enabled')" == "true" ]]; then
        kokoro_tor_install
    fi

    kokoro_validate
    kokoro_xray_restart
    kokoro_log "edge node ready"
    kokoro_log "pubkey for exit peer: $(kokoro_cfg '.multinode.local_pubkey')"
}

kokoro_edge_install