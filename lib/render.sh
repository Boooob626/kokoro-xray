#!/usr/bin/env bash
# kokoro-xray — render templates into live configs

source "$(cd -P -- "$(dirname -- "$0")" && pwd -P)/common.sh"

kokoro_render_file() {
    local tpl="$1" out="$2"
    local tmp
    tmp="$(mktemp)"
    cp "$tpl" "$tmp"
    while IFS= read -r line; do
        [[ "$line" =~ \{\{([A-Z0-9_]+)\}\} ]] || continue
        local key="${BASH_REMATCH[1]}"
        local val
        val="$(kokoro_cfg ".placeholders.${key} // empty" 2>/dev/null || true)"
        if [[ -z "$val" ]]; then
            case "$key" in
                UUID) val="$(kokoro_cfg '.inbound.uuid')" ;;
                XHTTP_PATH) val="$(kokoro_cfg '.inbound.xhttp_path')" ;;
                REALITY_PRIVATE_KEY) val="$(kokoro_cfg '.inbound.reality.private_key')" ;;
                REALITY_PUBLIC_KEY) val="$(kokoro_cfg '.inbound.reality.public_key')" ;;
                REALITY_DEST) val="$(kokoro_cfg '.inbound.reality.dest')" ;;
                REALITY_SNI) val="$(kokoro_cfg '.inbound.reality.server_names[0]')" ;;
                SHORT_ID) val="$(kokoro_cfg '.inbound.reality.short_ids[0]')" ;;
                CDN_DOMAIN) val="$(kokoro_cfg '.inbound.tls.cdn_domain')" ;;
                DOMAIN) val="$(kokoro_cfg '.inbound.tls.domain')" ;;
                WG_PRIVKEY) val="$(kokoro_cfg '.multinode.local_privkey')" ;;
                WG_PUBKEY) val="$(kokoro_cfg '.multinode.local_pubkey')" ;;
                PEER_PUBKEY) val="$(kokoro_cfg '.multinode.exit_pubkey')" ;;
                PEER_ENDPOINT) val="$(kokoro_cfg '.multinode.exit_ip'):$(kokoro_cfg '.multinode.exit_port')" ;;
                LOCAL_WG_IP) val="$(kokoro_cfg '.multinode.local_wg_ip')" ;;
                PEER_WG_IP) val="$(kokoro_cfg '.multinode.peer_wg_ip')" ;;
                EXIT_WG_PORT) val="$(kokoro_cfg '.multinode.exit_port')" ;;
                TOR_SOCKS) val="127.0.0.1:$(kokoro_cfg '.tor.socks_port')" ;;
                *) val="" ;;
            esac
        fi
        sed -i "s|{{${key}}}|${val}|g" "$tmp"
    done <"$tpl"
    install -d "$(dirname "$out")"
    mv "$tmp" "$out"
}

kokoro_build_edge_xray() {
    local root out mode parts
    root="$(kokoro_project_root)"
    out="$(kokoro_cfg '.paths.xray_config')"
    mode="$(kokoro_cfg '.inbound.mode')"
    parts=()

    case "$mode" in
        reality | both) parts+=("${root}/templates/xray/inbound-reality.json") ;;
    esac
    case "$mode" in
        tls | both) parts+=("${root}/templates/xray/inbound-tls.json") ;;
    esac

    parts+=(
        "${root}/templates/xray/outbounds-edge.json"
        "${root}/templates/xray/routing-edge.json"
        "${root}/templates/xray/policy.json"
        "${root}/templates/xray/log.json"
    )

    jq -s '
        {
          log: (.[] | select(has("log")) | .log),
          inbounds: ([.[] | select(has("inbounds")) | .inbounds[]] ),
          outbounds: ([.[] | select(has("outbounds")) | .outbounds[]] ),
          routing: (.[] | select(has("routing")) | .routing),
          policy: (.[] | select(has("policy")) | .policy)
        }
    ' "${parts[@]}" >"${out}.tmp"

    # placeholder substitution on assembled json
    local keys=(
        UUID XHTTP_PATH REALITY_PRIVATE_KEY REALITY_DEST REALITY_SNI SHORT_ID
        CDN_DOMAIN WG_PRIVKEY WG_PUBKEY PEER_PUBKEY PEER_ENDPOINT LOCAL_WG_IP
    )
    local k v
    for k in "${keys[@]}"; do
        v="$(kokoro_render_val "$k")"
        sed -i "s|{{${k}}}|${v}|g" "${out}.tmp"
    done

    # tor outbound
    if [[ "$(kokoro_cfg '.tor.enabled')" == "true" ]]; then
        jq '.outbounds += [{"tag":"TOR","protocol":"socks","settings":{"servers":[{"address":"127.0.0.1","port":9050}]}}]' \
            "${out}.tmp" >"${out}.tmp2"
        jq '.routing.rules = [{"type":"field","domain":["regexp:\\.onion$"],"outboundTag":"TOR"}] + .routing.rules' \
            "${out}.tmp2" >"${out}.tmp"
        rm -f "${out}.tmp2"
    fi

    # multinode wg outbound + routing
    if [[ "$(kokoro_cfg '.multinode.enabled')" == "true" ]]; then
        local wg_tpl="${root}/templates/xray/outbound-wg.json"
        local wg
        wg="$(mktemp)"
        cp "$wg_tpl" "$wg"
        for k in WG_PRIVKEY WG_PUBKEY PEER_PUBKEY PEER_ENDPOINT LOCAL_WG_IP; do
            sed -i "s|{{${k}}}|$(kokoro_render_val "$k")|g" "$wg"
        done
        if [[ "$(kokoro_cfg '.multinode.finalmask')" == "true" ]]; then
            jq '.outbounds[0].streamSettings = {"finalmask":{"udp":[{"type":"header-wireguard"}]}}' "$wg" >"${wg}.fm"
            mv "${wg}.fm" "$wg"
        fi
        jq --slurpfile w "$wg" '.outbounds += $w[0].outbounds' "${out}.tmp" >"${out}.tmp2"
        mv "${out}.tmp2" "${out}.tmp"
        local preset
        preset="$(kokoro_cfg '.routing.preset')"
        case "$preset" in
            all-to-exit)
                jq '.routing.rules = [{"type":"field","network":"tcp,udp","outboundTag":"WG_TO_EXIT"}] + (.routing.rules | map(select(.outboundTag != "DIRECT" or .network == null)))' \
                    "${out}.tmp" >"${out}.tmp2"
                ;;
            ai-to-exit|*)
                jq '.routing.rules = [{"type":"field","domain":["geosite:category-ai-!cn","domain:openai.com","domain:claude.ai","domain:gemini.google.com"],"outboundTag":"WG_TO_EXIT"}] + .routing.rules' \
                    "${out}.tmp" >"${out}.tmp2"
                ;;
        esac
        mv "${out}.tmp2" "${out}.tmp"
    fi

    # reality-only: xray owns :443 directly (no Caddy L4 needed)
    if [[ "$mode" == "reality" ]]; then
        jq '(.inbounds[] | select(.tag=="REALITY_XHTTP_IN") | .listen) = "0.0.0.0"
            | (.inbounds[] | select(.tag=="REALITY_XHTTP_IN") | .port) = 443' \
            "${out}.tmp" >"${out}.tmp2"
        mv "${out}.tmp2" "${out}.tmp"
    fi

    mv "${out}.tmp" "$out"
    chmod 600 "$out"
}

kokoro_render_val() {
    local key="$1"
    case "$key" in
        UUID) kokoro_cfg '.inbound.uuid' ;;
        XHTTP_PATH) kokoro_cfg '.inbound.xhttp_path' ;;
        REALITY_PRIVATE_KEY) kokoro_cfg '.inbound.reality.private_key' ;;
        REALITY_DEST) kokoro_cfg '.inbound.reality.dest' ;;
        REALITY_SNI) kokoro_cfg '.inbound.reality.server_names[0]' ;;
        SHORT_ID) kokoro_cfg '.inbound.reality.short_ids[0]' ;;
        CDN_DOMAIN) kokoro_cfg '.inbound.tls.cdn_domain' ;;
        DOMAIN) kokoro_cfg '.inbound.tls.domain' ;;
        WG_PRIVKEY) kokoro_cfg '.multinode.local_privkey' ;;
        WG_PUBKEY) kokoro_cfg '.multinode.local_pubkey' ;;
        PEER_PUBKEY) kokoro_cfg '.multinode.exit_pubkey' ;;
        PEER_ENDPOINT) printf '%s:%s' "$(kokoro_cfg '.multinode.exit_ip')" "$(kokoro_cfg '.multinode.exit_port')" ;;
        LOCAL_WG_IP) kokoro_cfg '.multinode.local_wg_ip' ;;
        PEER_WG_IP) kokoro_cfg '.multinode.peer_wg_ip' ;;
        EXIT_WG_PORT) kokoro_cfg '.multinode.exit_port' ;;
        *) printf '' ;;
    esac
}

kokoro_build_exit_xray() {
    local root out tpl
    root="$(kokoro_project_root)"
    out="$(kokoro_cfg '.paths.xray_config')"
    tpl="${root}/templates/xray/exit-wg.json"
    cp "$tpl" "${out}.tmp"
    local k
    for k in WG_PRIVKEY WG_PUBKEY PEER_PUBKEY PEER_WG_IP EXIT_WG_PORT; do
        sed -i "s|{{${k}}}|$(kokoro_render_val "$k")|g" "${out}.tmp"
    done
    if [[ "$(kokoro_cfg '.multinode.finalmask')" == "true" ]]; then
        jq '.inbounds[0].streamSettings = {"finalmask":{"udp":[{"type":"header-wireguard"}]}}' "${out}.tmp" >"${out}.tmp2"
        mv "${out}.tmp2" "${out}.tmp"
    fi
    mv "${out}.tmp" "$out"
    chmod 600 "$out"
}

kokoro_build_edge_caddy() {
    local root out tpl
    root="$(kokoro_project_root)"
    out="$(kokoro_cfg '.paths.caddyfile')"
    tpl="${root}/templates/caddy/Caddyfile.edge"
    kokoro_render_file "$tpl" "$out"
}