#!/usr/bin/env bash
# kokoro-xray — shared constants and helpers

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

readonly GREEN='\033[32m'
readonly YELLOW='\033[33m'
readonly RED='\033[31m'
readonly CYAN='\033[36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

readonly KOKORO_HOME="${HOME}/.kokoro-xray"
readonly KOKORO_CONFIG="${KOKORO_HOME}/config.json"

kokoro_project_root() {
    local src="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
    local dir
    dir="$(cd -P -- "$(dirname -- "$src")/.." && pwd -P)"
    printf '%s\n' "$dir"
}

kokoro_ensure_config() {
    mkdir -p "${KOKORO_HOME}"
    if [[ ! -f "${KOKORO_CONFIG}" ]]; then
        cp "$(kokoro_project_root)/config.defaults.json" "${KOKORO_CONFIG}"
    fi
}

kokoro_cfg() {
    local query="$1"
    jq -r "$query" "${KOKORO_CONFIG}"
}

kokoro_cfg_set() {
    local query="$1"
    local value="$2"
    local tmp
    tmp="$(mktemp)"
    jq "$query = $value" "${KOKORO_CONFIG}" >"$tmp"
    mv "$tmp" "${KOKORO_CONFIG}"
}

kokoro_cfg_set_str() {
    local key="$1"
    local value="$2"
    local tmp
    tmp="$(mktemp)"
    jq --arg v "$value" "$key = \$v" "${KOKORO_CONFIG}" >"$tmp"
    mv "$tmp" "${KOKORO_CONFIG}"
}

kokoro_log() {
    echo -e "${GREEN}[kokoro]${NC} $*"
}

kokoro_warn() {
    echo -e "${YELLOW}[warn]${NC} $*" >&2
}

kokoro_die() {
    echo -e "${RED}[error]${NC} $*" >&2
    exit 1
}

kokoro_need_root() {
    [[ "${EUID}" -eq 0 ]] || kokoro_die "run as root"
}

kokoro_need_cmd() {
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1 || kokoro_die "missing command: $cmd"
}

kokoro_load_i18n() {
    local root lang file
    root="$(kokoro_project_root)"
    lang="$(kokoro_cfg '.language')"
    if [[ "$lang" == "auto" || -z "$lang" || "$lang" == "null" ]]; then
        lang="${LANG%%_*}"
        lang="${lang:-en}"
    fi
    file="${root}/i18n/${lang}.json"
    [[ -f "$file" ]] || file="${root}/i18n/en.json"
    [[ -f "$file" ]] || kokoro_die "i18n file not found"
    KOKORO_I18N_FILE="$file"
}

kokoro_t() {
    local key="$1"
    jq -r --arg k "$key" '.[$k] // $k' "${KOKORO_I18N_FILE}"
}