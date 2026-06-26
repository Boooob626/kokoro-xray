#!/usr/bin/env bash
# kokoro-xray — interactive edge onboarding

: "${KOKORO_ROOT:=$(cd -P -- "$(dirname -- "$0")/.." && pwd -P)}"
source "${KOKORO_ROOT}/lib/common.sh"

kokoro_onboard_edge() {
    local mode cdn email sni dest

    if [[ ! -t 0 ]]; then
        return 0
    fi

    read -r -p "Inbound mode [reality/tls] (tls): " mode
    mode="${mode:-tls}"
    kokoro_cfg_set_str '.inbound.mode' "$mode"

    if [[ "$mode" == "tls" ]]; then
        read -r -p "CDN domain (e.g. cdn.example.com): " cdn
        [[ -n "$cdn" ]] && kokoro_cfg_set_str '.inbound.tls.cdn_domain' "$cdn"
        read -r -p "ACME email: " email
        [[ -n "$email" ]] && kokoro_cfg_set_str '.inbound.tls.acme_email' "$email"
        kokoro_onboard_tls_ports
        kokoro_warn "Cloudflare: use Full (Strict) SSL; DNS-only during first cert if HTTP-01 fails"
    fi

    kokoro_onboard_hy2 "$cdn"

    if [[ "$mode" == "reality" ]]; then
        local do_scan=false scan_args=()
        if [[ "${KOKORO_APPLY_EDGE:-}" == "true" ]]; then
            do_scan=true
            kokoro_log "scanning REALITY targets (--apply-edge)..."
        else
            read -r -p "Scan for REALITY target? [Y/n]: " scan_ans
            [[ ! "$scan_ans" =~ ^[Nn]$ ]] && do_scan=true
        fi

        if [[ "$do_scan" == "true" ]]; then
            # shellcheck source=lib/reality-scan.sh
            source "${KOKORO_ROOT}/lib/reality-scan.sh"
            if [[ -t 0 ]]; then
                scan_args=(--limit 10 --select)
            else
                scan_args=(--limit 10 --apply)
            fi
            if kokoro_reality_scan "${scan_args[@]}"; then
                kokoro_log "REALITY target set from scan"
            else
                kokoro_warn "scan found no valid targets — enter manually"
                read -r -p "REALITY SNI [www.sky.com]: " sni
                sni="${sni:-www.sky.com}"
                kokoro_cfg_set '.inbound.reality.server_names' "[\"${sni}\"]"
                read -r -p "REALITY dest [${sni}:443]: " dest
                dest="${dest:-${sni}:443}"
                kokoro_cfg_set_str '.inbound.reality.dest' "$dest"
            fi
        else
            read -r -p "REALITY SNI [www.sky.com]: " sni
            sni="${sni:-www.sky.com}"
            kokoro_cfg_set '.inbound.reality.server_names' "[\"${sni}\"]"
            read -r -p "REALITY dest [${sni}:443]: " dest
            dest="${dest:-${sni}:443}"
            kokoro_cfg_set_str '.inbound.reality.dest' "$dest"
        fi
    fi

    kokoro_onboard_firewall
}

kokoro_onboard_tls_ports() {
    local extra json_arr port

    read -r -p "Extra TLS TCP ports for jump (comma, blank none): " extra
    json_arr="443"
    while IFS= read -r port; do
        port="${port//[[:space:]]/}"
        [[ -n "$port" ]] || continue
        if [[ "$port" =~ ^[0-9]+$ && "$port" -ge 1 && "$port" -le 65535 ]]; then
            [[ "$port" == "443" ]] || json_arr="${json_arr},${port}"
        else
            kokoro_warn "skip invalid TLS port: $port"
        fi
    done < <(printf '%s' "$extra" | tr ',' '\n')

    kokoro_cfg_set '.inbound.tls.ports' "[${json_arr}]"
}

kokoro_onboard_hy2() {
    local cdn="${1:-}" current prompt ans port sni fallback_sni
    current="$(kokoro_cfg '.inbound.hy2.enabled // false')"
    if [[ "$current" == "true" ]]; then
        prompt="Enable HY2 UDP acceleration? [Y/n]: "
    else
        prompt="Enable HY2 UDP acceleration? [y/N]: "
    fi

    read -r -p "$prompt" ans
    if [[ -z "$ans" ]]; then
        [[ "$current" == "true" ]] || { kokoro_cfg_set '.inbound.hy2.enabled' 'false'; return 0; }
    elif [[ "$ans" =~ ^[Yy]$ ]]; then
        :
    else
        kokoro_cfg_set '.inbound.hy2.enabled' 'false'
        return 0
    fi

    kokoro_cfg_set '.inbound.hy2.enabled' 'true'
    read -r -p "HY2 UDP port [443]: " port
    port="${port:-443}"
    if [[ ! "$port" =~ ^[0-9]+$ || "$port" -lt 1 || "$port" -gt 65535 ]]; then
        kokoro_warn "invalid HY2 port, using 443"
        port=443
    fi
    kokoro_cfg_set '.inbound.hy2.port' "$port"

    fallback_sni="$cdn"
    [[ -n "$fallback_sni" ]] || fallback_sni="$(kokoro_cfg '.inbound.hy2.sni')"
    [[ -n "$fallback_sni" && "$fallback_sni" != "null" ]] || fallback_sni="$(kokoro_cfg '.inbound.tls.domain')"
    [[ -n "$fallback_sni" && "$fallback_sni" != "null" ]] || fallback_sni="kokoro-hy2.local"
    read -r -p "HY2 SNI [${fallback_sni}]: " sni
    sni="${sni:-$fallback_sni}"
    kokoro_cfg_set_str '.inbound.hy2.sni' "$sni"
    kokoro_warn "HY2 uses UDP; open ${port}/udp in the VPS firewall/security group"
}

kokoro_onboard_firewall() {
    local ans ssh extra detected json_arr
    if [[ ! -t 0 ]]; then
        return 0
    fi

    read -r -p "Enable UFW firewall? [Y/n]: " ans
    if [[ "$ans" =~ ^[Nn]$ ]]; then
        kokoro_cfg_set '.firewall.enabled' 'false'
        return 0
    fi
    kokoro_cfg_set '.firewall.enabled' 'true'

    detected="$(bash -c "source '${KOKORO_ROOT}/lib/firewall.sh'; kokoro_firewall_detect_ssh")"
    read -r -p "SSH port [auto/${detected}]: " ssh
    if [[ -n "$ssh" ]]; then
        kokoro_cfg_set '.firewall.ssh_port' "$ssh"
    else
        kokoro_cfg_set '.firewall.ssh_port' '0'
    fi

    read -r -p "Extra allow ports (e.g. 5555,5000-5010): " extra
    if [[ -z "$extra" ]]; then
        kokoro_cfg_set '.firewall.extra_allow' '[]'
        return 0
    fi

    json_arr="$(printf '%s' "$extra" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
        | awk 'NF {printf "%s\"%s\"", (n++?",":""), $0}')"
    kokoro_cfg_set '.firewall.extra_allow' "[${json_arr}]"
}
