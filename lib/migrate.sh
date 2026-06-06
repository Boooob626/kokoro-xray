#!/usr/bin/env bash
# kokoro-xray — config schema migration

source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"

kokoro_migrate() {
    local ver tmp
    ver="$(kokoro_cfg '.version // "0.1.0"')"

    if [[ "$ver" == "0.1.0" ]]; then
        kokoro_migrate_v010_to_v020
        kokoro_cfg_set_str '.version' '0.2.0'
        kokoro_log "migrated config 0.1.0 → 0.2.0"
    fi

    if ! jq -e '.firewall' "${KOKORO_CONFIG}" >/dev/null 2>&1; then
        tmp="$(mktemp)"
        jq '.firewall = {"enabled": true, "ssh_port": 0, "extra_allow": []}' \
            "${KOKORO_CONFIG}" >"$tmp"
        mv "$tmp" "${KOKORO_CONFIG}"
    fi
}

kokoro_migrate_v010_to_v020() {
    local tmp
    tmp="$(mktemp)"

    # Move secrets from config.json → secrets.json
    if jq -e '.inbound.uuid // empty' "${KOKORO_CONFIG}" >/dev/null 2>&1; then
        local uuid path priv pub sid edge_priv edge_pub exit_pub
        uuid="$(jq -r '.inbound.uuid // ""' "${KOKORO_CONFIG}")"
        path="$(jq -r '.inbound.xhttp_path // ""' "${KOKORO_CONFIG}")"
        priv="$(jq -r '.inbound.reality.private_key // ""' "${KOKORO_CONFIG}")"
        pub="$(jq -r '.inbound.reality.public_key // ""' "${KOKORO_CONFIG}")"
        sid="$(jq -r '.inbound.reality.short_ids[0] // ""' "${KOKORO_CONFIG}")"
        edge_priv="$(jq -r '.multinode.local_privkey // ""' "${KOKORO_CONFIG}")"
        edge_pub="$(jq -r '.multinode.local_pubkey // ""' "${KOKORO_CONFIG}")"
        exit_pub="$(jq -r '.multinode.exit_pubkey // ""' "${KOKORO_CONFIG}")"

        jq \
            --arg uuid "$uuid" --arg path "$path" \
            --arg priv "$priv" --arg pub "$pub" --arg sid "$sid" \
            --arg epriv "$edge_priv" --arg epub "$edge_pub" \
            '.inbound.uuid = $uuid
             | .inbound.xhttp_path = $path
             | .inbound.reality.private_key = $priv
             | .inbound.reality.public_key = $pub
             | .inbound.reality.short_ids = [$sid]
             | .multinode.edge_wg_privkey = $epriv
             | .multinode.edge_wg_pubkey = $epub' \
            "${KOKORO_SECRETS}" >"$tmp"
        mv "$tmp" "${KOKORO_SECRETS}"
        chmod 600 "${KOKORO_SECRETS}"

        if [[ -n "$exit_pub" ]]; then
            kokoro_cfg_set_str '.multinode.peer_exit_pubkey' "$exit_pub"
        fi

        jq 'del(.inbound.uuid, .inbound.xhttp_path)
            | .inbound.reality |= del(.private_key, .public_key, .short_ids)
            | .multinode |= del(.local_privkey, .local_pubkey, .exit_pubkey)
            | .multinode.peer_exit_pubkey //= ""
            | .multinode.peer_edge_pubkey //= ""
            | .version = "0.2.0"
            | .caddy = {"version":"2.9.1","use_l4":true}
            | .paths.caddy_bin = "/usr/local/bin/caddy"
            | .paths.geo_dir = "/usr/local/share/xray"
            | .inbound.tls.acme_email //= ""' \
            "${KOKORO_CONFIG}" >"$tmp"
        mv "$tmp" "${KOKORO_CONFIG}"
    fi
}