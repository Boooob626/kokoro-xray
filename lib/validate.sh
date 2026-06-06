#!/usr/bin/env bash
# kokoro-xray — config validation

source "$(cd -P -- "$(dirname -- "$0")" && pwd -P)/common.sh"

kokoro_validate() {
    local xray_bin cfg caddyfile role
    xray_bin="$(kokoro_cfg '.paths.xray_bin')"
    cfg="$(kokoro_cfg '.paths.xray_config')"
    caddyfile="$(kokoro_cfg '.paths.caddyfile')"
    role="$(kokoro_cfg '.role')"

    [[ -f "$cfg" ]] || kokoro_die "missing xray config: $cfg"
    [[ -x "$xray_bin" ]] || kokoro_die "xray binary not found"
    "$xray_bin" run -test -config "$cfg" || kokoro_die "xray config test failed"

    if [[ "$role" == "edge" ]] && [[ -f "$caddyfile" ]]; then
        command -v caddy >/dev/null 2>&1 && caddy validate --config "$caddyfile" || kokoro_warn "caddy validate skipped or failed"
    fi
    kokoro_log "validation passed"
}