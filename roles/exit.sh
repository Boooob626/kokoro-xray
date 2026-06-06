#!/usr/bin/env bash
# kokoro-xray — exit node setup

export KOKORO_ROOT="$(cd -P -- "$(dirname -- "$0")/.." && pwd -P)"
KEEP_SECRETS=false
FORCE_SECRETS=false

for arg in "$@"; do
    case "$arg" in
        --keep-secrets) KEEP_SECRETS=true ;;
        --force-secrets) FORCE_SECRETS=true ;;
    esac
done

source "${KOKORO_ROOT}/lib/common.sh"
source "${KOKORO_ROOT}/lib/os.sh"
source "${KOKORO_ROOT}/lib/xray.sh"
source "${KOKORO_ROOT}/lib/keys.sh"
source "${KOKORO_ROOT}/lib/onboard.sh"
source "${KOKORO_ROOT}/lib/apply.sh"
source "${KOKORO_ROOT}/lib/network-tune.sh"

kokoro_exit_random_port() {
    printf '%s\n' "$((49152 + RANDOM % 16384))"
}

kokoro_exit_ensure_port() {
    local port
    port="$(kokoro_cfg '.multinode.exit_port')"
    if [[ ! "$port" =~ ^[0-9]+$ || "$port" -le 0 ]]; then
        port="$(kokoro_exit_random_port)"
        kokoro_cfg_set '.multinode.exit_port' "$port"
        kokoro_log "generated exit WG UDP port: $port"
    fi
}

kokoro_exit_install() {
    kokoro_need_root
    kokoro_ensure_state
    kokoro_cfg_set_str '.role' 'exit'
    kokoro_exit_ensure_port
    kokoro_onboard_firewall

    kokoro_install_deps
    kokoro_xray_install

    if [[ "$FORCE_SECRETS" == "true" ]]; then
        kokoro_gen_secrets
    elif [[ "$KEEP_SECRETS" == "true" ]] && kokoro_secrets_exist; then
        kokoro_log "keeping existing secrets"
    else
        if ! kokoro_secrets_exist; then
            kokoro_gen_secrets
        else
            kokoro_log "keeping existing secrets"
        fi
    fi

    if [[ -z "$(kokoro_cfg '.multinode.peer_edge_pubkey')" || "$(kokoro_cfg '.multinode.peer_edge_pubkey')" == "null" ]]; then
        if [[ -t 0 ]]; then
            local epub fm
            read -r -p "Edge WG public key (leave empty to pair later): " epub
            [[ -n "$epub" ]] && kokoro_cfg_set_str '.multinode.peer_edge_pubkey' "$epub"
            read -r -p "Use experimental FinalMask WG header? [y/N] " fm
            [[ "$fm" =~ ^[Yy]$ ]] && kokoro_cfg_set '.multinode.finalmask' 'true' || kokoro_cfg_set '.multinode.finalmask' 'false'
        else
            kokoro_warn "multinode.peer_edge_pubkey not set — run: kokoro-xray pair"
        fi
    fi

    if [[ -z "$(kokoro_cfg '.multinode.peer_edge_pubkey')" || "$(kokoro_cfg '.multinode.peer_edge_pubkey')" == "null" ]]; then
        kokoro_warn "exit configured but not applied — missing edge WG public key"
        kokoro_warn "install edge, run kokoro-xray pair, then run kokoro-xray apply on exit"
    else
        kokoro_apply
    fi
    kokoro_network_tune || true
    kokoro_log "exit pubkey (paste on edge): $(kokoro_sec '.multinode.exit_wg_pubkey')"
    kokoro_log "exit WG UDP port (paste on edge): $(kokoro_cfg '.multinode.exit_port')"
}

kokoro_exit_install
