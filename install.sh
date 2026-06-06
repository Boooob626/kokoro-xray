#!/usr/bin/env bash
# kokoro-xray — bootstrap installer

set -euo pipefail

REPO_URL="${KOKORO_REPO_URL:-https://github.com/takashi728/kokoro-xray}"
INSTALL_DIR="${KOKORO_INSTALL_DIR:-/opt/kokoro-xray}"

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
export PATH

RED='\033[31m'; GREEN='\033[32m'; NC='\033[0m'

die() { echo -e "${RED}[error]${NC} $*" >&2; exit 1; }
log() { echo -e "${GREEN}[kokoro]${NC} $*"; }

[[ "${EUID}" -eq 0 ]] || die "run as root"

SCRIPT_DIR="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"

install_bootstrap_deps() {
    if command -v git >/dev/null 2>&1; then
        return 0
    fi
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        case "${ID:-}" in
            debian | ubuntu)
                apt-get update -qq
                DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ca-certificates curl git
                ;;
            *)
                die "git required for remote install (unsupported OS: ${ID:-unknown})"
                ;;
        esac
    else
        die "git required for remote install"
    fi
}

install_local() {
    local src="$SCRIPT_DIR"
    [[ -f "${src}/kokoro-xray.sh" ]] || die "run from repo root or set KOKORO_REPO_URL"
    install -d "$INSTALL_DIR"
    cp -a "${src}/." "$INSTALL_DIR/"
    chmod +x "${INSTALL_DIR}/kokoro-xray.sh" "${INSTALL_DIR}/install.sh"
    chmod +x "${INSTALL_DIR}/lib/"*.sh "${INSTALL_DIR}/roles/"*.sh 2>/dev/null || true
    chmod 644 "${INSTALL_DIR}/data/"*.txt 2>/dev/null || true
}

install_remote() {
    install_bootstrap_deps
    rm -rf "$INSTALL_DIR"
    git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
    chmod +x "${INSTALL_DIR}/kokoro-xray.sh" "${INSTALL_DIR}/install.sh"
    chmod +x "${INSTALL_DIR}/lib/"*.sh "${INSTALL_DIR}/roles/"*.sh 2>/dev/null || true
    chmod 644 "${INSTALL_DIR}/data/"*.txt 2>/dev/null || true
}

if [[ -f "${SCRIPT_DIR}/kokoro-xray.sh" ]]; then
    install_local
else
    install_remote
fi

ln -sf "${INSTALL_DIR}/kokoro-xray.sh" /usr/local/bin/kokoro-xray

install -d -m 700 "${HOME}/.kokoro-xray"
if [[ ! -f "${HOME}/.kokoro-xray/config.json" ]]; then
    cp "${INSTALL_DIR}/config.defaults.json" "${HOME}/.kokoro-xray/config.json"
    chmod 644 "${HOME}/.kokoro-xray/config.json"
fi
if [[ ! -f "${HOME}/.kokoro-xray/secrets.json" ]]; then
    cp "${INSTALL_DIR}/secrets.defaults.json" "${HOME}/.kokoro-xray/secrets.json"
    chmod 600 "${HOME}/.kokoro-xray/secrets.json"
fi

log "installed to ${INSTALL_DIR}"
log "run: kokoro-xray"

case "${1:-}" in
    --edge) exec "${INSTALL_DIR}/kokoro-xray.sh" edge "${@:2}" ;;
    --exit) exec "${INSTALL_DIR}/kokoro-xray.sh" exit "${@:2}" ;;
    *) exec "${INSTALL_DIR}/kokoro-xray.sh" "${@:1}" ;;
esac
