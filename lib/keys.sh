#!/usr/bin/env bash
# kokoro-xray — key and secret generation

source "$(cd -P -- "$(dirname -- "$0")" && pwd -P)/common.sh"

kokoro_rand_path() {
    local chars='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
    local out="/"
    local i c
    for i in $(seq 1 24); do
        c="${chars:RANDOM%${#chars}:1}"
        out+="$c"
    done
    printf '%s\n' "$out"
}

kokoro_rand_short_id() {
    openssl rand -hex 4
}

kokoro_gen_uuid() {
    local xray_bin
    xray_bin="$(kokoro_cfg '.paths.xray_bin')"
    if [[ -x "$xray_bin" ]]; then
        "$xray_bin" uuid
        return
    fi
    uuidgen | tr '[:upper:]' '[:lower:]'
}

kokoro_gen_reality_keys() {
    local xray_bin priv pub
    xray_bin="$(kokoro_cfg '.paths.xray_bin')"
    [[ -x "$xray_bin" ]] || kokoro_die "xray not installed"
    read -r priv pub < <("$xray_bin" x25519 | awk '/PrivateKey:|Password:/{print $2}' | paste - -)
    if [[ -z "$priv" || -z "$pub" ]]; then
        priv="$("$xray_bin" x25519 | awk '/Private key:/{print $3}')"
        pub="$("$xray_bin" x25519 | awk '/Public key:/{print $3}')"
    fi
    kokoro_cfg_set_str '.inbound.reality.private_key' "$priv"
    kokoro_cfg_set_str '.inbound.reality.public_key' "$pub"
}

kokoro_gen_wg_keys() {
    local priv pub
    priv="$(wg genkey)"
    pub="$(printf '%s' "$priv" | wg pubkey)"
    kokoro_cfg_set_str '.multinode.local_privkey' "$priv"
    kokoro_cfg_set_str '.multinode.local_pubkey' "$pub"
}

kokoro_gen_edge_secrets() {
    local uuid path sid
    uuid="$(kokoro_gen_uuid)"
    path="$(kokoro_rand_path)"
    sid="$(kokoro_rand_short_id)"
    kokoro_cfg_set_str '.inbound.uuid' "$uuid"
    kokoro_cfg_set_str '.inbound.xhttp_path' "$path"
    kokoro_cfg_set '.inbound.reality.short_ids' "[\"${sid}\"]"
    kokoro_gen_reality_keys
    kokoro_gen_wg_keys
}

kokoro_gen_exit_secrets() {
    kokoro_gen_wg_keys
}