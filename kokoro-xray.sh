#!/usr/bin/env bash
# kokoro-xray — main entrypoint

set -euo pipefail

SCRIPT_PATH="$(readlink -f "$0")"
export KOKORO_ROOT="$(cd -P -- "$(dirname -- "$SCRIPT_PATH")" && pwd -P)"
source "${KOKORO_ROOT}/lib/common.sh"

kokoro_ensure_state

menu() {
    echo -e "${CYAN}${BOLD}kokoro-xray${NC} minimal shell xray manager"
    echo ""
    echo "  1) Install / update edge node"
    echo "  2) Install / update exit node"
    echo "  3) Show share links"
    echo "  4) Apply config (render + reload)"
    echo "  5) Pair edge <-> exit (WG keys)"
    echo "  6) Show status"
    echo "  7) Validate configs"
    echo "  8) Scan REALITY targets"
    echo "  9) Tune network (TFO + BBR)"
    echo "  q) Quit"
    echo ""
}

kokoro_dispatch() {
    local cmd="${1:-}"
    shift || true
    case "$cmd" in
        edge)    bash "${KOKORO_ROOT}/roles/edge.sh" "$@" ;;
        exit)    bash "${KOKORO_ROOT}/roles/exit.sh" "$@" ;;
        link)    source "${KOKORO_ROOT}/lib/link.sh"; kokoro_link_show "$@" ;;
        firewall)
            shift || true
            source "${KOKORO_ROOT}/lib/firewall.sh"
            kokoro_firewall_cli "$@"
            ;;
        apply)   source "${KOKORO_ROOT}/lib/apply.sh"; kokoro_apply ;;
        pair)    bash "${KOKORO_ROOT}/roles/pair.sh" ;;
        status)  source "${KOKORO_ROOT}/lib/health.sh"; kokoro_health ;;
        validate) bash "${KOKORO_ROOT}/lib/validate.sh" ;;
        reality)
            case "${1:-}" in
                scan) shift; source "${KOKORO_ROOT}/lib/reality-scan.sh"; kokoro_reality_scan "$@" ;;
                *) kokoro_die "usage: kokoro-xray reality scan [--apply|--select]" ;;
            esac ;;
        tune)
            shift || true
            source "${KOKORO_ROOT}/lib/network-tune.sh"
            kokoro_need_root
            kokoro_network_tune "$@"
            ;;
        reinstall)
            kokoro_need_root
            bash "${KOKORO_ROOT}/install.sh" --clean-install "$@"
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
    read -r -p "Choice: " choice
    case "$choice" in
        1) bash "${KOKORO_ROOT}/roles/edge.sh" --keep-secrets --apply-edge ;;
        2) bash "${KOKORO_ROOT}/roles/exit.sh" --keep-secrets ;;
        3) source "${KOKORO_ROOT}/lib/link.sh"; kokoro_link_show ;;
        4) source "${KOKORO_ROOT}/lib/apply.sh"; kokoro_apply ;;
        5) bash "${KOKORO_ROOT}/roles/pair.sh" ;;
        6) source "${KOKORO_ROOT}/lib/health.sh"; kokoro_health ;;
        7) bash "${KOKORO_ROOT}/lib/validate.sh" ;;
        8) source "${KOKORO_ROOT}/lib/reality-scan.sh"; kokoro_reality_scan --limit 10 ;;
        9) source "${KOKORO_ROOT}/lib/network-tune.sh"; kokoro_need_root; kokoro_network_tune ;;
        q|Q) exit 0 ;;
        *) kokoro_warn "invalid choice" ;;
    esac
    echo ""
done
