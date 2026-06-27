#!/usr/bin/env bash
# kokoro-xray — optional Cloudflare DNS-01 helper

source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"

kokoro_cf_dns01_hint() {
    if [[ -n "${CF_API_TOKEN:-}" && -n "${CF_ZONE_ID:-}" ]]; then
        kokoro_log "CF_API_TOKEN set — use acme.sh --dns dns_cf for orange-cloud domains"
        return 0
    fi
    kokoro_warn "CF CDN tip: set DNS-only (grey cloud) during first ACME, then enable proxy"
    kokoro_warn "Or export CF_API_TOKEN + CF_ZONE_ID for DNS-01"
}
