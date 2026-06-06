#!/usr/bin/env bash
# kokoro-xray — bootstrap installer
#
#   curl -fsSL .../install.sh | bash
#   or: bash install.sh [--edge|--exit]

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

install_local() {
    src="$SCRIPT_DIR"
    if [[ ! -f "${src}/kokoro-xray.sh" ]]; then
        die "run from repo root or set KOKORO_REPO_URL"
    fi
    install -d "$INSTALL_DIR"
    cp -a "${src}/." "$INSTALL_DIR/"
    chmod +x "${INSTALL_DIR}/kokoro-xray.sh" "${INSTALL_DIR}/install.sh"
    chmod +x "${INSTALL_DIR}/lib/"*.sh "${INSTALL_DIR}/roles/"*.sh
}

install_remote() {
    command -v git >/dev/null 2>&1 || die "git required for remote install"
    rm -rf "$INSTALL_DIR"
    git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
    chmod +x "${INSTALL_DIR}/kokoro-xray.sh" "${INSTALL_DIR}/install.sh"
    chmod +x "${INSTALL_DIR}/lib/"*.sh "${INSTALL_DIR}/roles/"*.sh
}

if [[ -f "${SCRIPT_DIR}/kokoro-xray.sh" ]]; then
    install_local
else
    install_remote
fi

ln -sf "${INSTALL_DIR}/kokoro-xray.sh" /usr/local/bin/kokoro-xray

mkdir -p "${HOME}/.kokoro-xray"
if [[ ! -f "${HOME}/.kokoro-xray/config.json" ]]; then
    cp "${INSTALL_DIR}/config.defaults.json" "${HOME}/.kokoro-xray/config.json"
fi

log "installed to ${INSTALL_DIR}"
log "run: kokoro-xray"

case "${1:-}" in
    --edge) exec "${INSTALL_DIR}/kokoro-xray.sh" edge ;;
    --exit) exec "${INSTALL_DIR}/kokoro-xray.sh" exit ;;
    *) exec "${INSTALL_DIR}/kokoro-xray.sh" ;;
esac