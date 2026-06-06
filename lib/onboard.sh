#!/usr/bin/env bash
# kokoro-xray — interactive edge onboarding

: "${KOKORO_ROOT:=$(cd -P -- "$(dirname -- "$0")/.." && pwd -P)}"
source "${KOKORO_ROOT}/lib/common.sh"

kokoro_onboard_edge() {
    local mode cdn email sni dest preset

    if [[ ! -t 0 ]]; then
        return 0
    fi

    read -r -p "Inbound mode [reality/tls/both] (both): " mode
    mode="${mode:-both}"
    kokoro_cfg_set_str '.inbound.mode' "$mode"

    if [[ "$mode" == "tls" || "$mode" == "both" ]]; then
        read -r -p "CDN domain (e.g. cdn.example.com): " cdn
        [[ -n "$cdn" ]] && kokoro_cfg_set_str '.inbound.tls.cdn_domain' "$cdn"
        read -r -p "ACME email: " email
        [[ -n "$email" ]] && kokoro_cfg_set_str '.inbound.tls.acme_email' "$email"
        kokoro_warn "Cloudflare: use Full (Strict) SSL; DNS-only during first cert if HTTP-01 fails"
    fi

    if [[ "$mode" == "reality" || "$mode" == "both" ]]; then
        read -r -p "Scan for REALITY target? [Y/n]: " do_scan
        if [[ ! "$do_scan" =~ ^[Nn]$ ]]; then
            # shellcheck source=lib/reality-scan.sh
            source "${KOKORO_ROOT}/lib/reality-scan.sh"
            if kokoro_reality_scan --limit 5 --apply; then
                kokoro_log "REALITY target set from scan"
            else
                kokoro_warn "scan found no valid targets — enter manually"
                local sni dest
                read -r -p "REALITY SNI [www.sky.com]: " sni
                sni="${sni:-www.sky.com}"
                kokoro_cfg_set '.inbound.reality.server_names' "[\"${sni}\"]"
                read -r -p "REALITY dest [${sni}:443]: " dest
                dest="${dest:-${sni}:443}"
                kokoro_cfg_set_str '.inbound.reality.dest' "$dest"
            fi
        else
            local sni dest
            read -r -p "REALITY SNI [www.sky.com]: " sni
            sni="${sni:-www.sky.com}"
            kokoro_cfg_set '.inbound.reality.server_names' "[\"${sni}\"]"
            read -r -p "REALITY dest [${sni}:443]: " dest
            dest="${dest:-${sni}:443}"
            kokoro_cfg_set_str '.inbound.reality.dest' "$dest"
        fi
    fi

    read -r -p "Routing preset [ai-to-exit/all-to-exit] (ai-to-exit): " preset
    preset="${preset:-ai-to-exit}"
    kokoro_cfg_set_str '.routing.preset' "$preset"
}