# kokoro-xray

Small shell manager for Xray edge/exit deployments.

The scripts keep state in JSON, render configs with `jq`, validate before reload, and avoid large framework dependencies.

## Supported Modes

- Edge single-node: VLESS XHTTP TLS by default, REALITY or both when selected
- Optional HY2/Hysteria2 UDP edge on the same node
- Edge + exit: edge forwards traffic to an exit over WireGuard
- TLS edge: Caddy handles ACME and HTTPS routing
- REALITY edge: Xray serves public `:443` directly

For a ranked speed/latency setup guide, see [`docs/top3-pipelines.md`](docs/top3-pipelines.md).

## Requirements

- Debian or Ubuntu
- Root access
- `443/tcp` open on edge nodes
- `443/udp` open when HY2 is enabled, or the custom `inbound.hy2.port`
- `80/tcp` open on TLS edge nodes for ACME
- Exit node UDP port open when using edge + exit, default `51820/udp`

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/Boooob626/kokoro-xray/main/install.sh | sudo bash
```

Install and immediately start edge setup:

```bash
curl -fsSL https://raw.githubusercontent.com/Boooob626/kokoro-xray/main/install.sh | sudo bash -s -- --edge
```

During edge setup, press Enter for `tls` unless you need `reality` or `both`. HY2 is enabled by default as a separate UDP acceleration option; keep port `443` unless you need a custom UDP port, and set the HY2 SNI to your domain.

Install and immediately start exit setup:

```bash
curl -fsSL https://raw.githubusercontent.com/Boooob626/kokoro-xray/main/install.sh | sudo bash -s -- --exit
```

## Update

Normal update keeps existing state:

```bash
curl -fsSL https://raw.githubusercontent.com/Boooob626/kokoro-xray/main/install.sh | sudo bash
sudo kokoro-xray apply
sudo kokoro-xray tune
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

```bash
kokoro-xray link
kokoro-xray link --json tls
kokoro-xray link --json hy2 --host VPS_IP_OR_DOMAIN
kokoro-xray link --json hy2 --host auto6
```

Use `--host auto6` when HY2 should connect to the VPS IPv6 address while the SNI domain only has an A record.

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

## Files

- Install dir: `/opt/kokoro-xray`
- Command symlink: `/usr/local/bin/kokoro-xray`
- Settings: `~/.kokoro-xray/config.json`
- Secrets: `~/.kokoro-xray/secrets.json`
- Xray config: `/usr/local/etc/xray/config.json`
- Caddyfile: `/etc/caddy/Caddyfile`

## Notes

- Xray downloads are verified with upstream SHA256 digest files.
- Default TLS mode uses the official Caddy release binary with checksum verification; `both` mode builds Caddy with caddy-l4 only when selected.
- If distro Go is too old, Caddy builds use a managed Go toolchain under `/usr/local/kokoro-go`.
- UFW defaults to deny incoming and allow outgoing when firewall support is enabled.

## License

MIT
