#!/usr/bin/env bash
# kokoro-xray — main menu

set -euo pipefail

ROOT="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"
# shellcheck source=lib/common.sh
source "${ROOT}/lib/common.sh"

kokoro_ensure_config
kokoro_load_i18n

menu() {
    echo -e "${CYAN}${BOLD}kokoro-xray${NC} $(kokoro_t menu_subtitle)"
    echo ""
    echo "  1) $(kokoro_t menu_edge)"
    echo "  2) $(kokoro_t menu_exit)"
    echo "  3) $(kokoro_t menu_link)"
    echo "  4) $(kokoro_t menu_tor_on)"
    echo "  5) $(kokoro_t menu_tor_off)"
    echo "  6) $(kokoro_t menu_multinode)"
    echo "  7) $(kokoro_t menu_validate)"
    echo "  q) $(kokoro_t menu_quit)"
    echo ""
}

kokoro_multinode_prompt() {
    local ip pub
    read -r -p "$(kokoro_t prompt_exit_ip): " ip
    read -r -p "$(kokoro_t prompt_exit_pubkey): " pub
    kokoro_cfg_set_str '.multinode.exit_ip' "$ip"
    kokoro_cfg_set_str '.multinode.exit_pubkey' "$pub"
    kokoro_cfg_set '.multinode.enabled' 'true'
    kokoro_log "$(kokoro_t multinode_saved)"
}

case "${1:-}" in
    edge)
        bash "${ROOT}/roles/edge.sh" ;;
    exit)
        bash "${ROOT}/roles/exit.sh" ;;
    link)
        bash "${ROOT}/roles/client.sh" ;;
    validate)
        bash "${ROOT}/lib/validate.sh" ;;
    *)
        if [[ ! -t 0 ]]; then
            menu
            exit 0
        fi
        while true; do
            menu
            read -r -p "$(kokoro_t menu_choice): " choice
            case "$choice" in
                1) bash "${ROOT}/roles/edge.sh" ;;
                2) bash "${ROOT}/roles/exit.sh" ;;
                3) bash "${ROOT}/roles/client.sh" ;;
                4)
                    source "${ROOT}/lib/tor.sh"
                    kokoro_tor_enable
                    ;;
                5)
                    source "${ROOT}/lib/tor.sh"
                    kokoro_tor_disable
                    ;;
                6) kokoro_multinode_prompt ;;
                7)
                    source "${ROOT}/lib/validate.sh"
                    kokoro_validate
                    ;;
                q|Q) exit 0 ;;
                *) kokoro_warn "$(kokoro_t invalid_choice)" ;;
            esac
            echo ""
        done
        ;;
esac