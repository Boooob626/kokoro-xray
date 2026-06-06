#!/usr/bin/env bash
# kokoro-xray — share link generator

source "$(cd -P -- "$(dirname -- "$0")/../lib" && pwd -P)/common.sh"

kokoro_share_link() {
    kokoro_ensure_config
    local uuid path sni pub sid mode host security
    uuid="$(kokoro_cfg '.inbound.uuid')"
    path="$(kokoro_cfg '.inbound.xhttp_path')"
    mode="$(kokoro_cfg '.inbound.mode')"
    sni="$(kokoro_cfg '.inbound.reality.server_names[0]')"
    pub="$(kokoro_cfg '.inbound.reality.public_key')"
    sid="$(kokoro_cfg '.inbound.reality.short_ids[0]')"

    if [[ "$mode" == "tls" || "$mode" == "both" ]]; then
        host="$(kokoro_cfg '.inbound.tls.cdn_domain')"
        security="tls"
        echo "vless://${uuid}@${host}:443?encryption=none&security=${security}&type=xhttp&path=${path}&host=${host}#kokoro-tls"
    fi

    if [[ "$mode" == "reality" || "$mode" == "both" ]]; then
        host="$(curl -4 -s ifconfig.me 2>/dev/null || echo 'YOUR_VPS_IP')"
        security="reality"
        echo "vless://${uuid}@${host}:443?encryption=none&security=${security}&type=xhttp&path=${path}&pbk=${pub}&fp=chrome&sni=${sni}&sid=${sid}#kokoro-reality"
    fi
}

kokoro_share_link