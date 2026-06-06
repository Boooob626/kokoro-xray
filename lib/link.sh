#!/usr/bin/env bash
# kokoro-xray — VLESS share links + terminal QR

: "${KOKORO_ROOT:=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)}"
source "${KOKORO_ROOT}/lib/common.sh"

kokoro_link_tls_url() {
    kokoro_ensure_state
    local uuid path mode cdn
    mode="$(kokoro_cfg '.inbound.mode')"
    [[ "$mode" == "tls" || "$mode" == "both" ]] || return 0
    uuid="$(kokoro_sec '.inbound.uuid')"
    path="$(kokoro_sec '.inbound.xhttp_path')"
    cdn="$(kokoro_cfg '.inbound.tls.cdn_domain')"
    [[ -n "$cdn" && "$cdn" != "null" ]] || return 0
    printf 'vless://%s@%s:443?encryption=none&security=tls&type=xhttp&path=%s&host=%s#kokoro-tls\n' \
        "$uuid" "$cdn" "$path" "$cdn"
}

kokoro_link_reality_url() {
    kokoro_ensure_state
    local uuid path sni pub sid mode host
    mode="$(kokoro_cfg '.inbound.mode')"
    [[ "$mode" == "reality" || "$mode" == "both" ]] || return 0
    uuid="$(kokoro_sec '.inbound.uuid')"
    path="$(kokoro_sec '.inbound.xhttp_path')"
    sni="$(kokoro_cfg '.inbound.reality.server_names[0]')"
    pub="$(kokoro_sec '.inbound.reality.public_key')"
    sid="$(kokoro_sec '.inbound.reality.short_ids[0]')"
    host="$(curl -4 -s ifconfig.me 2>/dev/null || echo 'YOUR_VPS_IP')"
    printf 'vless://%s@%s:443?encryption=none&security=reality&type=xhttp&path=%s&pbk=%s&fp=chrome&sni=%s&sid=%s#kokoro-reality\n' \
        "$uuid" "$host" "$path" "$pub" "$sni" "$sid"
}

kokoro_link_qr_ensure() {
    command -v qrencode >/dev/null 2>&1 && return 0
    if [[ "${EUID}" -eq 0 ]]; then
        # shellcheck source=lib/os.sh
        source "${KOKORO_ROOT}/lib/os.sh"
        kokoro_pkg_install qrencode
        return 0
    fi
    kokoro_die "qrencode not found — install qrencode or run as root"
}

kokoro_link_qr() {
    local url="$1" label="$2"
    [[ -n "$url" ]] || return 0
    kokoro_link_qr_ensure
    echo "--- ${label} (scan with client app) ---"
    printf '%s' "$url" | qrencode -t ANSIUTF8 -m 2
    echo ""
}

kokoro_link_show() {
    local show_qr=false
    local reality_url tls_url

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --qr) show_qr=true; shift ;;
            -h|--help)
                cat <<'EOF'
kokoro-xray link — VLESS share URLs

Usage:
  kokoro-xray link
  kokoro-xray link --qr

Options:
  --qr   Print terminal QR codes (requires qrencode)
EOF
                return 0
                ;;
            *) kokoro_die "unknown option: $1 (try --help)" ;;
        esac
    done

    reality_url="$(kokoro_link_reality_url)"
    tls_url="$(kokoro_link_tls_url)"

    [[ -n "$reality_url" || -n "$tls_url" ]] || kokoro_die "no links for role/mode (edge required)"

    if [[ -n "$reality_url" ]]; then
        printf '%s\n' "$reality_url"
        [[ "$show_qr" == "true" ]] && kokoro_link_qr "$reality_url" "REALITY"
    fi

    if [[ -n "$tls_url" ]]; then
        printf '%s\n' "$tls_url"
        [[ "$show_qr" == "true" ]] && kokoro_link_qr "$tls_url" "TLS"
    fi
}