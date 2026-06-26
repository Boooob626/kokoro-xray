#!/usr/bin/env bash
# kokoro-xray — render dispatcher (jq only, no sed)

source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"

kokoro_render_hy2_cert() {
    local enabled cert key name pin tmp
    enabled="$(kokoro_cfg '.inbound.hy2.enabled // false')"
    [[ "$enabled" == "true" ]] || return 0

    cert="$(kokoro_cfg '.paths.hy2_cert')"
    key="$(kokoro_cfg '.paths.hy2_key')"
    name="$(kokoro_cfg '.inbound.hy2.sni')"
    [[ -n "$name" && "$name" != "null" ]] || name="$(kokoro_cfg '.inbound.tls.domain')"
    [[ -n "$name" && "$name" != "null" ]] || name="kokoro-hy2.local"

    install -d -m 700 "$(dirname "$cert")"
    install -d -m 700 "$(dirname "$key")"
    if [[ ! -s "$cert" || ! -s "$key" ]]; then
        command -v openssl >/dev/null 2>&1 || kokoro_die "openssl required to generate HY2 certificate"
        openssl req -x509 -newkey rsa:2048 -nodes \
            -keyout "$key" \
            -out "$cert" \
            -days 3650 \
            -subj "/CN=${name}" \
            -addext "subjectAltName=DNS:${name}" >/dev/null 2>&1
        chmod 600 "$key"
        chmod 644 "$cert"
    fi

    pin="$(openssl x509 -in "$cert" -outform der | openssl dgst -sha256 -r | awk '{print $1}')"
    tmp="$(mktemp)"
    jq --arg pin "$pin" '.inbound.hy2.pinned_peer_cert_sha256 = $pin' "${KOKORO_SECRETS}" >"$tmp"
    mv "$tmp" "${KOKORO_SECRETS}"
    chmod 600 "${KOKORO_SECRETS}"
}

kokoro_render_xray() {
    local out
    kokoro_render_hy2_cert
    out="$(kokoro_cfg '.paths.xray_config')"
    install -d "$(dirname "$out")"
    jq -n -f "${KOKORO_ROOT}/lib/render.jq" \
        --slurpfile cfg "${KOKORO_CONFIG}" \
        --slurpfile sec "${KOKORO_SECRETS}" \
        >"${out}.tmp"
    mv "${out}.tmp" "$out"
    chmod 600 "$out"
}

kokoro_render_caddy() {
    local out mode
    mode="$(kokoro_cfg '.inbound.mode')"
    [[ "$mode" == "tls" ]] || return 0
    out="$(kokoro_cfg '.paths.caddyfile')"
    install -d "$(dirname "$out")"
    jq -n -r -f "${KOKORO_ROOT}/lib/caddy.jq" \
        --slurpfile cfg "${KOKORO_CONFIG}" \
        --slurpfile sec "${KOKORO_SECRETS}" \
        >"${out}.tmp"
    mv "${out}.tmp" "$out"
}

kokoro_render() {
    local role
    role="$(kokoro_cfg '.role')"
    case "$role" in
        edge)
            kokoro_render_xray
            kokoro_render_caddy
            ;;
        exit)
            kokoro_render_xray
            ;;
        *)
            kokoro_die "cannot render: role not set"
            ;;
    esac
}
