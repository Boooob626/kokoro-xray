#!/usr/bin/env bash
# kokoro-xray — exchange WG peer keys between edge and exit

export KOKORO_ROOT="$(cd -P -- "$(dirname -- "$0")/.." && pwd -P)"
source "${KOKORO_ROOT}/lib/common.sh"
source "${KOKORO_ROOT}/lib/apply.sh"

kokoro_pair() {
    local role
    kokoro_ensure_state
    role="$(kokoro_cfg '.role')"

    case "$role" in
        edge)
            local ip port pub fm
            read -r -p "Exit node IP: " ip
            read -r -p "Exit WG UDP port: " port
            [[ "$port" =~ ^[0-9]+$ && "$port" -ge 1 && "$port" -le 65535 ]] || kokoro_die "invalid exit WG UDP port: $port"
            read -r -p "Exit WG public key: " pub
            kokoro_cfg_set_str '.multinode.exit_ip' "$ip"
            kokoro_cfg_set '.multinode.exit_port' "$port"
            kokoro_cfg_set_str '.multinode.peer_exit_pubkey' "$pub"
            kokoro_cfg_set '.multinode.enabled' 'true'
            read -r -p "Use experimental FinalMask WG header? [y/N] " fm
            [[ "$fm" =~ ^[Yy]$ ]] && kokoro_cfg_set '.multinode.finalmask' 'true' || kokoro_cfg_set '.multinode.finalmask' 'false'
            kokoro_apply
            echo ""
            echo "=== Give this to exit node ==="
            echo "edge_wg_pubkey=$(kokoro_sec '.multinode.edge_wg_pubkey')"
            ;;
        exit)
            local epub fm
            read -r -p "Edge WG public key: " epub
            kokoro_cfg_set_str '.multinode.peer_edge_pubkey' "$epub"
            read -r -p "Use experimental FinalMask WG header? [y/N] " fm
            [[ "$fm" =~ ^[Yy]$ ]] && kokoro_cfg_set '.multinode.finalmask' 'true' || kokoro_cfg_set '.multinode.finalmask' 'false'
            kokoro_apply
            echo ""
            echo "=== Give this to edge node ==="
            echo "exit_wg_pubkey=$(kokoro_sec '.multinode.exit_wg_pubkey')"
            echo "exit_wg_port=$(kokoro_cfg '.multinode.exit_port')"
            echo "exit_ip=$(curl -4 -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')"
            ;;
        *)
            kokoro_die "set role first (run edge or exit install)"
            ;;
    esac
}

kokoro_pair
