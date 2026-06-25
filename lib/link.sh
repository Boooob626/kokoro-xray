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
    printf 'vless://%s@%s:443?encryption=none&security=tls&type=xhttp&path=%s&host=%s&sni=%s&fp=chrome&alpn=h2#kokoro-tls\n' \
        "$uuid" "$cdn" "$path" "$cdn" "$cdn"
}

kokoro_link_reality_url() {
    kokoro_ensure_state
    local host="${1:-}" uuid path sni pub sid mode
    mode="$(kokoro_cfg '.inbound.mode')"
    [[ "$mode" == "reality" || "$mode" == "both" ]] || return 0
    uuid="$(kokoro_sec '.inbound.uuid')"
    path="$(kokoro_sec '.inbound.xhttp_path')"
    sni="$(kokoro_cfg '.inbound.reality.server_names[0]')"
    pub="$(kokoro_sec '.inbound.reality.public_key')"
    sid="$(kokoro_sec '.inbound.reality.short_ids[0]')"
    [[ -n "$host" ]] || host="$(curl -4 -s ifconfig.me 2>/dev/null || echo 'YOUR_VPS_IP')"
    printf 'vless://%s@%s:443?encryption=none&security=reality&type=xhttp&path=%s&pbk=%s&fp=chrome&sni=%s&sid=%s#kokoro-reality\n' \
        "$uuid" "$host" "$path" "$pub" "$sni" "$sid"
}

kokoro_link_hy2_enabled() {
    [[ "$(kokoro_cfg '.inbound.hy2.enabled // false')" == "true" ]]
}

kokoro_link_hy2_sni() {
    local sni
    sni="$(kokoro_cfg '.inbound.hy2.sni')"
    [[ -n "$sni" && "$sni" != "null" ]] || sni="$(kokoro_cfg '.inbound.tls.domain')"
    [[ -n "$sni" && "$sni" != "null" ]] || sni="kokoro-hy2.local"
    printf '%s\n' "$sni"
}

kokoro_link_hy2_url() {
    kokoro_ensure_state
    local host="${1:-}" auth port sni pin
    kokoro_link_hy2_enabled || return 0
    [[ -n "$host" ]] || host="YOUR_VPS_IP_OR_DOMAIN"
    auth="$(kokoro_sec '.inbound.hy2.auth')"
    port="$(kokoro_cfg '.inbound.hy2.port')"
    sni="$(kokoro_link_hy2_sni)"
    pin="$(kokoro_sec '.inbound.hy2.pinned_peer_cert_sha256')"
    [[ -n "$pin" && "$pin" != "null" ]] || pin="PIN_AFTER_APPLY"
    printf 'hysteria2://%s@%s:%s?sni=%s&pinSHA256=%s&alpn=h3#kokoro-hy2\n' \
        "$auth" "$host" "$port" "$sni" "$pin"
}

kokoro_link_hy2_json() {
    kokoro_ensure_state
    local host="${1:-}" auth port sni pin
    kokoro_link_hy2_enabled || return 1
    [[ -n "$host" ]] || kokoro_die "HY2 JSON export requires --host VPS_IP_OR_DOMAIN"
    auth="$(kokoro_sec '.inbound.hy2.auth')"
    port="$(kokoro_cfg '.inbound.hy2.port')"
    sni="$(kokoro_link_hy2_sni)"
    pin="$(kokoro_sec '.inbound.hy2.pinned_peer_cert_sha256')"
    [[ -n "$pin" && "$pin" != "null" ]] || kokoro_die "HY2 certificate pin missing; run: sudo kokoro-xray apply"

    jq -n \
        --arg host "$host" \
        --arg auth "$auth" \
        --arg sni "$sni" \
        --arg pin "$pin" \
        --argjson port "$port" \
        '{
          log: { loglevel: "warning" },
          inbounds: [
            {
              tag: "socks-in",
              listen: "127.0.0.1",
              port: 10808,
              protocol: "socks",
              settings: { udp: true }
            },
            {
              tag: "http-in",
              listen: "127.0.0.1",
              port: 10809,
              protocol: "http"
            }
          ],
          outbounds: [
            {
              tag: "kokoro-hy2",
              protocol: "hysteria",
              settings: {
                version: 2,
                address: $host,
                port: $port
              },
              streamSettings: {
                network: "hysteria",
                security: "tls",
                tlsSettings: {
                  serverName: $sni,
                  fingerprint: "chrome",
                  alpn: ["h3"],
                  pinnedPeerCertSha256: $pin
                },
                hysteriaSettings: {
                  version: 2,
                  auth: $auth,
                  udpIdleTimeout: 60
                }
              }
            },
            { tag: "DIRECT", protocol: "freedom" },
            { tag: "BLOCK", protocol: "blackhole" }
          ],
          routing: {
            domainStrategy: "AsIs",
            rules: [
              {
                type: "field",
                ip: [
                  "0.0.0.0/8",
                  "10.0.0.0/8",
                  "100.64.0.0/10",
                  "127.0.0.0/8",
                  "169.254.0.0/16",
                  "172.16.0.0/12",
                  "192.0.0.0/24",
                  "192.0.2.0/24",
                  "192.168.0.0/16",
                  "198.18.0.0/15",
                  "198.51.100.0/24",
                  "203.0.113.0/24",
                  "::1/128",
                  "fc00::/7",
                  "fe80::/10"
                ],
                outboundTag: "BLOCK"
              },
              { type: "field", protocol: ["bittorrent"], outboundTag: "BLOCK" },
              { type: "field", network: "tcp,udp", outboundTag: "kokoro-hy2" }
            ]
          }
        }'
}

kokoro_link_tls_json() {
    kokoro_ensure_state
    local uuid path mode cdn
    mode="$(kokoro_cfg '.inbound.mode')"
    [[ "$mode" == "tls" || "$mode" == "both" ]] || return 1
    uuid="$(kokoro_sec '.inbound.uuid')"
    path="$(kokoro_sec '.inbound.xhttp_path')"
    cdn="$(kokoro_cfg '.inbound.tls.cdn_domain')"
    [[ -n "$cdn" && "$cdn" != "null" ]] || return 1

    jq -n \
        --arg uuid "$uuid" \
        --arg path "$path" \
        --arg cdn "$cdn" \
        '{
          log: { loglevel: "warning" },
          dns: {
            servers: [
              "https://cloudflare-dns.com/dns-query",
              "https://1.1.1.1/dns-query",
              "https://base.dns.mullvad.net/dns-query",
              "https://extended.dns.mullvad.net/dns-query"
            ],
            queryStrategy: "UseIPv4"
          },
          inbounds: [
            {
              tag: "socks-in",
              listen: "127.0.0.1",
              port: 10808,
              protocol: "socks",
              settings: { udp: true }
            },
            {
              tag: "http-in",
              listen: "127.0.0.1",
              port: 10809,
              protocol: "http"
            }
          ],
          outbounds: [
            {
              tag: "kokoro-tls",
              protocol: "vless",
              settings: {
                vnext: [
                  {
                    address: $cdn,
                    port: 443,
                    users: [
                      {
                        id: $uuid,
                        encryption: "none",
                        flow: ""
                      }
                    ]
                  }
                ]
              },
              streamSettings: {
                network: "xhttp",
                security: "tls",
                tlsSettings: {
                  serverName: $cdn,
                  fingerprint: "chrome",
                  alpn: ["h2"]
                },
                xhttpSettings: {
                  path: $path,
                  host: $cdn,
                  mode: "auto",
                  xmux: {
                    maxConcurrency: "1-1",
                    hMaxRequestTimes: "600-900",
                    hMaxReusableSecs: "1800-3000"
                  },
                  xPaddingKey: "v",
                  xPaddingBytes: "16-96",
                  xPaddingHeader: "Referer",
                  xPaddingMethod: "tokenish",
                  uplinkHTTPMethod: "POST",
                  xPaddingObfsMode: true,
                  xPaddingPlacement: "queryInHeader",
                  scMaxEachPostBytes: 2000000,
                  uplinkDataPlacement: "body",
                  scMinPostsIntervalMs: 10
                }
              }
            },
            { tag: "DIRECT", protocol: "freedom" },
            { tag: "BLOCK", protocol: "blackhole" }
          ],
          routing: {
            domainStrategy: "IPIfNonMatch",
            rules: [
              {
                type: "field",
                domain: ["geosite:category-ads-all"],
                outboundTag: "BLOCK"
              },
              {
                type: "field",
                domain: [
                  "domain:dns.google",
                  "domain:dns.google.com",
                  "domain:doh.google",
                  "domain:google-public-dns-a.google.com",
                  "domain:google-public-dns-b.google.com"
                ],
                outboundTag: "BLOCK"
              },
              {
                type: "field",
                ip: [
                  "8.8.8.8",
                  "8.8.4.4",
                  "2001:4860:4860::8888",
                  "2001:4860:4860::8844"
                ],
                outboundTag: "BLOCK"
              },
              {
                type: "field",
                domain: [
                  "geosite:google",
                  "geosite:youtube",
                  "domain:gmail.com",
                  "domain:gemini.google.com",
                  "domain:gemini.google",
                  "domain:googleapis.cn",
                  "domain:googleapis-cn.com",
                  "domain:gstatic.cn",
                  "domain:gstatic-cn.com"
                ],
                outboundTag: "kokoro-tls"
              },
              {
                type: "field",
                ip: ["geoip:private"],
                outboundTag: "BLOCK"
              },
              {
                type: "field",
                domain: ["geosite:private"],
                outboundTag: "BLOCK"
              },
              {
                type: "field",
                protocol: ["bittorrent"],
                outboundTag: "BLOCK"
              },
              {
                type: "field",
                domain: [
                  "geosite:cn",
                  "geosite:geolocation-cn",
                  "regexp:.*\\.ru$",
                  "regexp:.*\\.su$",
                  "regexp:.*\\.xn--p1ai$"
                ],
                outboundTag: "BLOCK"
              },
              {
                type: "field",
                ip: ["geoip:cn"],
                outboundTag: "BLOCK"
              },
              {
                type: "field",
                ip: ["geoip:ru"],
                outboundTag: "BLOCK"
              },
              {
                type: "field",
                network: "tcp,udp",
                outboundTag: "kokoro-tls"
              }
            ]
          }
        }'
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
    local show_qr=false json_profile="" host=""
    local reality_url tls_url hy2_url

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --qr) show_qr=true; shift ;;
            --host)
                [[ -n "${2:-}" ]] || kokoro_die "--host requires a value"
                host="$2"
                shift 2
                ;;
            --json)
                if [[ $# -ge 2 && "${2:-}" != -* ]]; then
                    case "$2" in
                        tls|hy2) json_profile="$2" ;;
                        *) kokoro_die "unknown JSON profile: $2 (expected tls or hy2)" ;;
                    esac
                    shift 2
                else
                    json_profile="tls"
                    shift
                fi
                ;;
            -h|--help)
                cat <<'EOF'
kokoro-xray link — VLESS share URLs

Usage:
  kokoro-xray link
  kokoro-xray link --qr
  kokoro-xray link --json [tls]
  kokoro-xray link --json hy2 --host VPS_IP_OR_DOMAIN

Options:
  --host HOST     Public VPS IP or domain for generated client output
  --qr            Print terminal QR codes (requires qrencode)
  --json PROFILE  Print full Xray client JSON for tls or hy2
EOF
                return 0
                ;;
            *) kokoro_die "unknown option: $1 (try --help)" ;;
        esac
    done

    if [[ "$json_profile" == "tls" ]]; then
        kokoro_link_tls_json || kokoro_die "tls profile is unavailable for current mode"
        return 0
    elif [[ "$json_profile" == "hy2" ]]; then
        kokoro_link_hy2_json "$host" || kokoro_die "hy2 profile is unavailable; set inbound.hy2.enabled=true"
        return 0
    fi

    reality_url="$(kokoro_link_reality_url "$host")"
    tls_url="$(kokoro_link_tls_url)"
    hy2_url="$(kokoro_link_hy2_url "$host")"

    [[ -n "$reality_url" || -n "$tls_url" || -n "$hy2_url" ]] || kokoro_die "no links for role/mode (edge required)"

    if [[ -n "$reality_url" ]]; then
        printf '%s\n' "$reality_url"
        [[ "$show_qr" == "true" ]] && kokoro_link_qr "$reality_url" "REALITY"
    fi

    if [[ -n "$tls_url" ]]; then
        printf '%s\n' "$tls_url"
        [[ "$show_qr" == "true" ]] && kokoro_link_qr "$tls_url" "TLS"
    fi

    if [[ -n "$hy2_url" ]]; then
        printf '%s\n' "$hy2_url"
        [[ "$show_qr" == "true" ]] && kokoro_link_qr "$hy2_url" "HY2"
    fi
}
