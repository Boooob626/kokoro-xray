# Top 3 Xray setup pipelines

This repo is optimized for a small edge VPS, not for exposing every Xray-core
knob. Xray-core supports many protocol and transport combinations; Kokoro uses
the ones that are useful here: VLESS over XHTTP, REALITY/TLS security, HY2
over UDP, and WireGuard for edge-to-exit routing.

Primary references:

- Xray transport methods: https://xtls.github.io/en/config/transport.html
- XHTTP transport: https://xtls.github.io/en/config/transports/xhttp.html
- Hysteria/HY2 inbound: https://xtls.github.io/en/config/inbounds/hysteria.html
- REALITY transport security: https://xtls.github.io/en/config/transport.html#realityobject

## Support scan

Xray-core documented protocol/transport surface:

| Category | Documented options | Kokoro choice |
| --- | --- | --- |
| Inbound protocols | tunnel/dokodemo-door, HTTP, Shadowsocks, SOCKS, Trojan, VLESS, VMess, WireGuard, Hysteria, TUN | VLESS, Hysteria, WireGuard |
| Outbound protocols | Blackhole, DNS, Freedom, HTTP, Loopback, Shadowsocks, SOCKS, Trojan, VLESS, VMess, WireGuard, Hysteria | Freedom, Blackhole, WireGuard, client-side VLESS/Hysteria |
| Transport methods | RAW, XHTTP, mKCP, gRPC, WebSocket, HTTPUpgrade, Hysteria | XHTTP and Hysteria |
| Transport security | TLS, REALITY | TLS and REALITY |
| Extra features | Sockopt, routing, sniffing, mux/XUDP, policy, geodata | Sockopt, routing, sniffing, policy, geodata |

Repo implementation status:

| Xray feature | Repo status | Use here |
| --- | --- | --- |
| VLESS + XHTTP | Supported | Main TCP path for TLS/REALITY clients |
| REALITY | Supported | Domainless stealth fallback |
| TLS + Caddy | Supported | CDN-compatible TCP path |
| Hysteria2/HY2 | Supported | Fast UDP path, best latency when UDP is good |
| WireGuard outbound | Supported | Edge to exit node |
| gRPC / WebSocket / HTTPUpgrade | Not implemented | Add only if a client or CDN forces it |
| mKCP / raw TCP / QUIC transport | Not implemented | Not top-3 for this repo's current use |

## Ranking

### 1. HY2 over IPv6 UDP

Best for lowest delay and highest throughput when the VPS IPv6 route is good.
It avoids TCP head-of-line blocking and the repo exports HY2 JSON with
`UseIPv6`.

Server:

```bash
curl -fsSL https://raw.githubusercontent.com/Boooob626/kokoro-xray/main/install.sh | sudo bash
sudo kokoro-xray edge
sudo kokoro-xray apply
sudo kokoro-xray tune
```

Client JSON:

```bash
sudo kokoro-xray link --json hy2 --host auto6 | jq .
```

Firewall:

```bash
sudo ufw status verbose
```

Open the HY2 UDP port on IPv6 in the VPS provider firewall too. Default is
`443/udp`.

Use when:

- The VPS has IPv6.
- The client network allows UDP.
- Latency matters more than CDN cover.

Avoid when:

- The client ISP throttles UDP.
- The VPS IPv6 route is worse than IPv4.

### 2. TLS XHTTP with multi-port jump

Best TCP fallback. It works through ordinary TLS/CDN paths and can jump across
multiple HTTPS ports when one path is congested or blocked.

Server:

```bash
sudo jq '.inbound.mode = "tls" | .inbound.tls.ports = [443, 8443, 2053, 2083]' /root/.kokoro-xray/config.json > /tmp/kokoro.json
sudo mv /tmp/kokoro.json /root/.kokoro-xray/config.json
sudo kokoro-xray apply
sudo kokoro-xray tune
```

Client JSON:

```bash
sudo kokoro-xray link --json tls | jq .
```

Use when:

- UDP is unstable.
- CDN/TLS camouflage matters.
- The client app supports full Xray JSON import.

Avoid when:

- You need absolute lowest latency; HY2 usually wins if UDP is clean.

### 3. REALITY XHTTP

Best domainless TCP fallback. It does not need your own domain or certificate.
The scanner picks a target with TLS 1.3, ALPN h2, sane cert coverage, and
usable redirect behavior.

Server:

```bash
sudo kokoro-xray reality scan --apply
sudo jq '.inbound.mode = "reality"' /root/.kokoro-xray/config.json > /tmp/kokoro.json
sudo mv /tmp/kokoro.json /root/.kokoro-xray/config.json
sudo kokoro-xray apply
sudo kokoro-xray tune
```

Client link:

```bash
sudo kokoro-xray link
```

Use when:

- You do not want to depend on a domain.
- TLS/CDN setup is failing.
- You need a durable TCP fallback.

Avoid when:

- Your client only imports full JSON and not VLESS share links.

## Operating pipeline

1. Install or update.
2. Apply config.
3. Run `sudo kokoro-xray tune`.
4. Export HY2 IPv6 JSON first.
5. Keep TLS XHTTP JSON as TCP fallback.
6. Keep REALITY link as no-domain fallback.
7. Test from the real client network; routing quality decides the winner.

Commands:

```bash
curl -fsSL https://raw.githubusercontent.com/Boooob626/kokoro-xray/main/install.sh | sudo bash
sudo kokoro-xray apply
sudo kokoro-xray tune
sudo kokoro-xray link --json hy2 --host auto6 > hy2-ipv6.json
sudo kokoro-xray link --json tls > tls-xhttp.json
sudo kokoro-xray link
```

## What not to add yet

Do not add gRPC/WebSocket/HTTPUpgrade just because Xray supports them. They add
more code, more client branches, and more Caddy surface. Add one only when a
specific client or CDN requires that transport and the current top-3 paths fail.

## Legacy comparison: zxcvos/Xray-script

`zxcvos/Xray-script` is useful as a broad legacy feature map. It includes
Vision+REALITY, XHTTP+REALITY, Trojan+XHTTP+REALITY, mKCP+seed, fallback/SNI
split, Nginx UDS routing, Cloudflare WARP via Docker, and Xray API traffic
stats.

What Kokoro should learn:

- Traffic stats are useful, but only add Xray API/stats when users need quota
  accounting. It adds an API inbound and more policy fields.
- Vision fallback to XHTTP is a valid legacy TCP design, but Kokoro already has
  `both` mode with Caddy layer4 SNI split and XHTTP. Do not add Nginx UDS unless
  Caddy cannot cover a required SNI split.
- mKCP+seed is a niche bad-network latency fallback. Keep it out of the default
  top 3; HY2 is the better UDP path for this repo.
- WARP routing is useful for IP reputation or regional egress, but Docker/WARP is
  too heavy for the edge default. Prefer Kokoro's existing edge-to-exit
  WireGuard path first.
- Trojan+XHTTP+REALITY helps clients that do not support VLESS well. Add it only
  for a concrete client compatibility failure.

Do not import its full Nginx/Cloudreve/WARP stack into Kokoro. That repo is a
feature kitchen sink; Kokoro should stay a small Xray edge manager.

## Other repo idea scan

Repos sampled:

- `mack-a/v2ray-agent`
- `233boy/Xray`
- `MHSanaei/3x-ui`

Useful ideas to keep:

| Idea | Source pattern | Kokoro decision |
| --- | --- | --- |
| Salted subscription files | `v2ray-agent` builds per-user default/Clash/sing-box subscriptions | Worth adding later as `kokoro-xray sub`, but not needed for single-user raw JSON |
| Traffic counters | `Xray-script`, `233boy`, and `3x-ui` use Xray API/stats | Best next small feature if quota/usage matters |
| Health monitor | `3x-ui` can probe a tunnel and restart after repeated failures | Worth adding as a simple `systemd` timer only if real VPS drops appear |
| Backup/export | Panels keep DB/config backups | Kokoro can add `snapshot export` before adding any database/panel |
| Per-client expiry/quota/IP limit | `3x-ui` panel feature | Do not add until Kokoro supports multiple named clients |
| WARP routing | `v2ray-agent` and `3x-ui` route selected traffic through WARP | Add only if IP reputation or region egress becomes a real need |
| Dynamic ports/mKCP seed | `233boy/Xray` supports mKCP and seed changes | Keep out of default; HY2 is the better UDP path here |
| NAT64/IPv6-only hints | `v2ray-agent` handles IPv6-only host edge cases | Good doc idea if users run IPv6-only VPS |
| Panel/API/Bot | `3x-ui` has REST API and Telegram bot | Too heavy for Kokoro's shell-first design |

Best next feature if Kokoro grows:

```text
1. traffic: Xray API stats summary
2. sub: local JSON/subscription bundle export
3. snapshot export/import: portable backup for config + secrets
```

Skip for now:

```text
panel, database, Telegram bot, Docker WARP stack, Nginx stack, multi-protocol kitchen sink
```
