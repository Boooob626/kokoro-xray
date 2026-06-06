# kokoro-xray

Minimal pure-shell Xray manager. Rebuild of the Xray-script philosophy without Nginx compilation bloat.

## Features

- **Edge node** — VLESS + XHTTP + REALITY and/or TLS (Cloudflare CDN)
- **Exit node** — Xray-core WireGuard inbound (FinalMask optional)
- **Multi-hop** — Edge routes selected traffic to exit via WG tunnel
- **Tor** — `.onion` outbound via local Tor SOCKS
- **Caddy** — TLS termination and CDN origin (replaces Nginx)
- **Pure shell** — bash + jq at runtime; Python only in CI (future)

## Quick start

```bash
# From this repo (local dev)
sudo bash install.sh

# Edge (DE VPS)
sudo kokoro-xray edge

# Exit (NL VPS) — copy pubkey to edge
sudo kokoro-xray exit

# Share links
kokoro-xray link
```

Edit `~/.kokoro-xray/config.json` before install to set domains:

```json
{
  "inbound": {
    "mode": "both",
    "tls": {
      "cdn_domain": "cdn.example.com"
    }
  }
}
```

## Architecture

```
Client ──[VLESS XHTTP REALITY/TLS]──► Edge (DE) ──[WireGuard]──► Exit (NL) ──► Internet
                                         │
                                         ├── .onion → Tor
                                         └── other → direct / routed
```

## Layout

```
kokoro-xray.sh      main menu
install.sh          bootstrap → /opt/kokoro-xray
lib/                common, xray, caddy, tor, keys, render, validate
roles/              edge, exit, client
templates/          xray JSON + Caddyfile
~/.kokoro-xray/     runtime config
```

## Defaults

| Setting | Value |
|---------|-------|
| Install | bare-metal systemd |
| WG obfuscation | FinalMask `header-wireguard` on |
| Inbound | both REALITY + TLS |
| Routing preset | AI traffic → exit node |

## Requirements

- Debian 11+ or Ubuntu 20.04+
- root
- Edge: domain for CDN mode; open 443/tcp
- Exit: open UDP 51820 (or custom port)

## Status

v0.1.0 scaffold — edge/exit install, template render, validate. Caddy L4 SNI split for `both` mode is planned (P3).

## License

MIT