# kokoro-xray

Small shell manager for Xray edge/exit deployments.

The scripts keep state in JSON, render configs with `jq`, validate before reload, and avoid large framework dependencies.

## Supported Modes

- Edge single-node: VLESS XHTTP REALITY, TLS, or both
- Optional HY2/Hysteria2 UDP edge on the same node
- Edge + exit: edge forwards traffic to an exit over WireGuard
- TLS edge: Caddy handles ACME and HTTPS routing
- REALITY edge: Xray serves public `:443` directly

## Requirements

- Debian or Ubuntu
- Root access
- `443/tcp` open on edge nodes
- `443/udp` open when HY2 is enabled, or the custom `inbound.hy2.port`
- `80/tcp` open on TLS edge nodes for ACME
- Exit node UDP port open when using edge + exit, default `51820/udp`

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/takashi728/kokoro-xray/main/install.sh | sudo bash
```

Install and immediately start edge setup:

```bash
curl -fsSL https://raw.githubusercontent.com/takashi728/kokoro-xray/main/install.sh | sudo bash -s -- --edge
```

Install a test branch:

```bash
curl -fsSL https://raw.githubusercontent.com/Boooob626/kokoro-xray/testing/install.sh | sudo env KOKORO_REPO_URL=https://github.com/Boooob626/kokoro-xray bash -s -- --branch testing --edge
```

The installer first tries a prebuilt runtime asset from the latest GitHub release. That asset can bundle the repo plus Xray, `geoip.dat`, and `geosite.dat` so VPS setup avoids a second Xray download. If no asset exists, the installer falls back to the normal git clone path. Disable the fast path with:

```bash
curl -fsSL https://raw.githubusercontent.com/takashi728/kokoro-xray/main/install.sh | sudo env KOKORO_USE_PREBUILT=0 bash
```

Install and immediately start exit setup:

```bash
curl -fsSL https://raw.githubusercontent.com/takashi728/kokoro-xray/main/install.sh | sudo bash -s -- --exit
```

## Update

Normal update keeps existing state:

```bash
curl -fsSL https://raw.githubusercontent.com/takashi728/kokoro-xray/main/install.sh | sudo bash
sudo kokoro-xray apply
```

Clean reinstall removes `/opt/kokoro-xray` and keeps `~/.kokoro-xray`:

```bash
sudo kokoro-xray reinstall --branch main
sudo kokoro-xray apply
```

## Basic Flow

Single edge:

```bash
sudo kokoro-xray edge
sudo kokoro-xray apply
kokoro-xray link
kokoro-xray status
```

Edge + exit:

```bash
# On exit
sudo kokoro-xray exit

# On edge
sudo kokoro-xray edge
sudo kokoro-xray pair
sudo kokoro-xray apply

# Back on exit, paste edge peer info when prompted
sudo kokoro-xray pair
sudo kokoro-xray apply
```

## Client Output

Standard share links:

```bash
kokoro-xray link
```

TLS XHTTP JSON export for clients that support full JSON import:

```bash
kokoro-xray link --json tls
```

Use JSON export for TLS mode when the client app does not preserve advanced XHTTP settings from URL subscriptions.

HY2/Hysteria2 JSON export requires an explicit public host so the client points at the VPS address you actually use:

```bash
kokoro-xray link --json hy2 --host VPS_IP_OR_DOMAIN
```

HY2 uses Xray's native Hysteria2 protocol over UDP with TLS ALPN `h3`. Kokoro generates a local HY2 certificate on `sudo kokoro-xray apply`, stores its SHA-256 pin in `~/.kokoro-xray/secrets.json`, and emits that pin in the HY2 client JSON.

Enable HY2 before apply:

```bash
jq '.inbound.hy2.enabled = true | .inbound.hy2.sni = "your-domain.example"' ~/.kokoro-xray/config.json > /tmp/kokoro.json
install -m 644 /tmp/kokoro.json ~/.kokoro-xray/config.json
sudo kokoro-xray apply
kokoro-xray link --json hy2 --host VPS_IP_OR_DOMAIN
```

## Commands

| Command | Description |
| --- | --- |
| `edge [--keep-secrets]` | Install or update edge node |
| `exit [--keep-secrets]` | Install or update exit node |
| `apply` | Render, validate, and reload services |
| `pair` | Exchange edge/exit WireGuard peer info |
| `link [--json tls]` | Print client links or TLS JSON |
| `link --json hy2 --host HOST` | Print full Xray client JSON for HY2 |
| `status` | Show service and config status |
| `validate` | Validate rendered configs |
| `geodata` | Update geo data files |
| `firewall status` | Show UFW state |
| `firewall apply` | Re-apply configured UFW rules |
| `tune` | Apply optional network tuning |
| `reality scan` | Probe REALITY targets |
| `tor on\|off` | Optional exit-node Tor routing |
| `reinstall --branch main` | Clean reinstall code, keep state |

## REALITY Target Scan

```bash
kokoro-xray reality scan
kokoro-xray reality scan --domains www.sky.com,github.com
kokoro-xray reality scan --apply
sudo kokoro-xray apply
```

The scanner checks DNS, TLS 1.3, ALPN `h2`, certificate coverage, and redirect behavior.

## Files

- Install dir: `/opt/kokoro-xray`
- Command symlink: `/usr/local/bin/kokoro-xray`
- Settings: `~/.kokoro-xray/config.json`
- Secrets: `~/.kokoro-xray/secrets.json`
- Xray config: `/usr/local/etc/xray/config.json`
- Caddyfile: `/etc/caddy/Caddyfile`

## Notes

- Xray downloads are verified with upstream SHA256 digest files.
- Prebuilt runtime assets are optional; missing assets fall back to source install and verified Xray download.
- Caddy builds are pinned and rebuilt only when needed.
- If distro Go is too old, Caddy builds use a managed Go toolchain under `/usr/local/kokoro-go`.
- UFW defaults to deny incoming and allow outgoing when firewall support is enabled.

## License

MIT
