#!/usr/bin/env bash
# kokoro-xray — bootstrap installer

set -euo pipefail

REPO_URL="${KOKORO_REPO_URL:-https://github.com/takashi728/kokoro-xray}"
REPO_BRANCH="${KOKORO_REPO_BRANCH:-}"
INSTALL_DIR="${KOKORO_INSTALL_DIR:-/opt/kokoro-xray}"
USE_PREBUILT="${KOKORO_USE_PREBUILT:-1}"
PREBUILT_URL="${KOKORO_PREBUILT_URL:-}"
CLEAN_INSTALL=false
INSTALL_ARGS=()

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
export PATH

RED='\033[31m'; GREEN='\033[32m'; NC='\033[0m'

die() { echo -e "${RED}[error]${NC} $*" >&2; exit 1; }
log() { echo -e "${GREEN}[kokoro]${NC} $*"; }

[[ "${EUID}" -eq 0 ]] || die "run as root"

SCRIPT_DIR="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --clean-install)
            CLEAN_INSTALL=true
            shift
            ;;
        --branch)
            [[ -n "${2:-}" ]] || die "--branch requires a branch name"
            REPO_BRANCH="$2"
            shift 2
            ;;
        *)
            INSTALL_ARGS+=("$1")
            shift
            ;;
    esac
done

safe_install_dir() {
    [[ -n "$INSTALL_DIR" ]] || die "KOKORO_INSTALL_DIR is empty"
    [[ "$INSTALL_DIR" == /* ]] || die "KOKORO_INSTALL_DIR must be absolute: $INSTALL_DIR"

    case "$INSTALL_DIR" in
        /|/bin|/boot|/dev|/etc|/home|/lib|/lib64|/opt|/proc|/root|/run|/sbin|/sys|/tmp|/usr|/usr/local|/var)
            die "refusing unsafe install dir: $INSTALL_DIR"
            ;;
    esac

    if [[ -L "$INSTALL_DIR" ]]; then
        die "refusing symlink install dir: $INSTALL_DIR"
    fi
}

remove_install_dir() {
    safe_install_dir
    [[ -e "$INSTALL_DIR" ]] || return 0
    log "removing install files: $INSTALL_DIR"
    rm -rf -- "$INSTALL_DIR"
}

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

release_asset_arch() {
    case "$(uname -m)" in
        x86_64) printf 'amd64\n' ;;
        aarch64|arm64) printf 'arm64\n' ;;
        *) return 1 ;;
    esac
}

repo_latest_asset_url() {
    local repo arch
    [[ "$REPO_URL" =~ github.com[:/]+([^/]+)/([^/.]+)(\.git)?$ ]] || return 1
    repo="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    arch="$(release_asset_arch)" || return 1
    printf 'https://github.com/%s/releases/latest/download/kokoro-xray-runtime-linux-%s.tar.gz\n' "$repo" "$arch"
}

install_prebuilt() {
    local url tmp
    [[ "$USE_PREBUILT" != "0" && -z "$REPO_BRANCH" ]] || return 1
    command -v curl >/dev/null 2>&1 || return 1
    command -v tar >/dev/null 2>&1 || return 1
    url="$PREBUILT_URL"
    [[ -n "$url" ]] || url="$(repo_latest_asset_url)" || return 1

    tmp="$(mktemp -d)"
    if ! curl -fsSL "$url" -o "${tmp}/runtime.tar.gz"; then
        rm -rf "$tmp"
        return 1
    fi
    if curl -fsSL "${url}.sha256" -o "${tmp}/runtime.tar.gz.sha256" 2>/dev/null; then
        awk '{print $1 "  runtime.tar.gz"}' "${tmp}/runtime.tar.gz.sha256" >"${tmp}/runtime.tar.gz.sha256.check"
        (cd "$tmp" && sha256sum -c runtime.tar.gz.sha256.check) >/dev/null || die "prebuilt runtime checksum failed"
    fi

    remove_install_dir
    install -d "$INSTALL_DIR"
    tar -xzf "${tmp}/runtime.tar.gz" -C "$INSTALL_DIR" --strip-components=1
    rm -rf "$tmp"
    chmod +x "${INSTALL_DIR}/kokoro-xray.sh" "${INSTALL_DIR}/install.sh"
    chmod +x "${INSTALL_DIR}/lib/"*.sh "${INSTALL_DIR}/roles/"*.sh 2>/dev/null || true
    chmod +x "${INSTALL_DIR}/prebuilt/xray" 2>/dev/null || true
    chmod 644 "${INSTALL_DIR}/data/"*.txt "${INSTALL_DIR}/prebuilt/"*.dat 2>/dev/null || true
    log "installed from prebuilt runtime asset"
}

install_local() {
    local src="$SCRIPT_DIR"
    [[ -f "${src}/kokoro-xray.sh" ]] || die "run from repo root or set KOKORO_REPO_URL"
    if [[ "$CLEAN_INSTALL" == "true" ]]; then
        if [[ "$(readlink -f "$src")" == "$(readlink -f "$INSTALL_DIR" 2>/dev/null || printf '%s' "$INSTALL_DIR")" ]]; then
            die "clean reinstall from the live install dir requires --branch BRANCH"
        fi
        remove_install_dir
    fi
    install -d "$INSTALL_DIR"
    cp -a "${src}/." "$INSTALL_DIR/"
    chmod +x "${INSTALL_DIR}/kokoro-xray.sh" "${INSTALL_DIR}/install.sh"
    chmod +x "${INSTALL_DIR}/lib/"*.sh "${INSTALL_DIR}/roles/"*.sh 2>/dev/null || true
    chmod 644 "${INSTALL_DIR}/data/"*.txt 2>/dev/null || true
}

install_remote() {
    if install_prebuilt; then
        return 0
    fi
    install_bootstrap_deps
    remove_install_dir
    if [[ -n "$REPO_BRANCH" ]]; then
        git clone --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$INSTALL_DIR"
    else
        git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
    fi
    chmod +x "${INSTALL_DIR}/kokoro-xray.sh" "${INSTALL_DIR}/install.sh"
    chmod +x "${INSTALL_DIR}/lib/"*.sh "${INSTALL_DIR}/roles/"*.sh 2>/dev/null || true
    chmod 644 "${INSTALL_DIR}/data/"*.txt 2>/dev/null || true
}

if [[ -n "$REPO_BRANCH" ]]; then
    install_remote
elif [[ -f "${SCRIPT_DIR}/kokoro-xray.sh" ]]; then
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

run_installed() {
    if [[ ! -t 0 && -r /dev/tty ]]; then
        exec "$@" </dev/tty
    fi
    exec "$@"
}

case "${INSTALL_ARGS[0]:-}" in
    --edge) run_installed "${INSTALL_DIR}/kokoro-xray.sh" edge "${INSTALL_ARGS[@]:1}" ;;
    --exit) run_installed "${INSTALL_DIR}/kokoro-xray.sh" exit "${INSTALL_ARGS[@]:1}" ;;
    *) run_installed "${INSTALL_DIR}/kokoro-xray.sh" "${INSTALL_ARGS[@]}" ;;
esac
