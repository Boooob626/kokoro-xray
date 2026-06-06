# kokoro-xray

Minimal pure-shell Xray manager. Shell dispatches, jq renders.

## Features

- Edge: VLESS + XHTTP + REALITY and/or TLS (Cloudflare CDN)
- Exit: Xray-core WireGuard inbound (FinalMask optional)
- Multi-hop: edge routes traffic to exit via WG tunnel
- Tor: `.onion` outbound via local Tor SOCKS
- Caddy: xcaddy + caddy-l4 for REALITY/TLS SNI split on `:443`

## Quick start

```bash
# Install
curl -fsSL https://raw.githubusercontent.com/takashi728/kokoro-xray/main/install.sh | sudo bash

# Exit node (NL) first
sudo kokoro-xray exit

# Edge node (DE)
sudo kokoro-xray edge

# Pair / apply / links
sudo kokoro-xray pair
sudo kokoro-xray apply
kokoro-xray link
kokoro-xray status
```

## Commands

| Command | Description |
|---------|-------------|
| `edge [--keep-secrets]` | Install/update edge |
| `exit [--keep-secrets]` | Install/update exit |
| `apply` | Render → validate → reload |
| `pair` | Exchange WG peer keys |
| `link` | Share URLs |
| `status` | Service + peer health |
| `tor on\|off` | Toggle Tor routing + apply |
| `geodata` | Update geoip/geosite |
| `reality scan` | Probe hosts for TLS1.3+h2+SAN (no Apple/iCloud) |
| `reality scan --apply` | Pick best target and write config.json |

## REALITY target scan

Validates candidates against [REALITY requirements](https://github.com/XTLS/REALITY/blob/main/README.en.md) — **not** a bulk third-party import:

```bash
# Scan curated seeds from data/reality-seeds.txt
kokoro-xray reality scan

# Probe your own list + apply best to config
kokoro-xray reality scan --domains www.sky.com,github.com --apply
sudo kokoro-xray apply
```

Checks: DNS, TLS 1.3, ALPN `h2`, cert SAN, redirect rules. Rejects `apple`/`icloud` (per Xray-core).

## Config

- Settings: `~/.kokoro-xray/config.json`
- Secrets: `~/.kokoro-xray/secrets.json` (mode 600)

## Architecture

See [docs/architecture.md](docs/architecture.md).

## Requirements

- Debian 11+ or Ubuntu 20.04+
- root
- Edge: domain for CDN mode; ports 443/tcp, 80/tcp
- Exit: UDP 51820 (or custom)

## License

MIT