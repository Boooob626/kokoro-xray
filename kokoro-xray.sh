#!/usr/bin/env bash
# kokoro-xray — main entrypoint

set -euo pipefail

export KOKORO_ROOT="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"
source "${KOKORO_ROOT}/lib/common.sh"

kokoro_ensure_state
kokoro_load_i18n

menu() {
    echo -e "${CYAN}${BOLD}kokoro-xray${NC} $(kokoro_t menu_subtitle)"
    echo ""
    echo "  1) $(kokoro_t menu_edge)"
    echo "  2) $(kokoro_t menu_exit)"
    echo "  3) $(kokoro_t menu_link)"
    echo "  4) $(kokoro_t menu_apply)"
    echo "  5) $(kokoro_t menu_pair)"
    echo "  6) $(kokoro_t menu_tor_on)"
    echo "  7) $(kokoro_t menu_tor_off)"
    echo "  8) $(kokoro_t menu_status)"
    echo "  9) $(kokoro_t menu_validate)"
    echo "  q) $(kokoro_t menu_quit)"
    echo ""
}

kokoro_dispatch() {
    local cmd="${1:-}"
    shift || true
    case "$cmd" in
        edge)    bash "${KOKORO_ROOT}/roles/edge.sh" "$@" ;;
        exit)    bash "${KOKORO_ROOT}/roles/exit.sh" "$@" ;;
        link)    bash "${KOKORO_ROOT}/roles/client.sh" ;;
        apply)   source "${KOKORO_ROOT}/lib/apply.sh"; kokoro_apply ;;
        pair)    bash "${KOKORO_ROOT}/roles/pair.sh" ;;
        status)  source "${KOKORO_ROOT}/lib/health.sh"; kokoro_health ;;
        validate) bash "${KOKORO_ROOT}/lib/validate.sh" ;;
        tor)
            case "${1:-}" in
                on)  source "${KOKORO_ROOT}/lib/tor.sh"; kokoro_tor_enable ;;
                off) source "${KOKORO_ROOT}/lib/tor.sh"; kokoro_tor_disable ;;
                *) kokoro_die "usage: kokoro-xray tor on|off" ;;
            esac ;;
        geodata)
            source "${KOKORO_ROOT}/lib/geodata.sh"
            kokoro_need_root
            kokoro_geodata_update
            ;;
        *)
            return 1
            ;;
    esac
}

if kokoro_dispatch "${1:-}" "${@:2}"; then
    exit 0
fi

if [[ ! -t 0 ]]; then
    menu
    exit 0
fi

while true; do
    menu
    read -r -p "$(kokoro_t menu_choice): " choice
    case "$choice" in
        1) bash "${KOKORO_ROOT}/roles/edge.sh" --keep-secrets ;;
        2) bash "${KOKORO_ROOT}/roles/exit.sh" --keep-secrets ;;
        3) bash "${KOKORO_ROOT}/roles/client.sh" ;;
        4) source "${KOKORO_ROOT}/lib/apply.sh"; kokoro_apply ;;
        5) bash "${KOKORO_ROOT}/roles/pair.sh" ;;
        6) source "${KOKORO_ROOT}/lib/tor.sh"; kokoro_tor_enable ;;
        7) source "${KOKORO_ROOT}/lib/tor.sh"; kokoro_tor_disable ;;
        8) source "${KOKORO_ROOT}/lib/health.sh"; kokoro_health ;;
        9) bash "${KOKORO_ROOT}/lib/validate.sh" ;;
        q|Q) exit 0 ;;
        *) kokoro_warn "$(kokoro_t invalid_choice)" ;;
    esac
    echo ""
done