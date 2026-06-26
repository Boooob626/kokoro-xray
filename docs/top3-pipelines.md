# Top 3 Xray setup pipelines

Kokoro keeps only the paths useful for a small edge VPS: HY2 UDP, TLS XHTTP,
and REALITY XHTTP. Add other Xray transports only for a real client or CDN
failure.

References:

- Xray transport: https://xtls.github.io/en/config/transport.html
- XHTTP: https://xtls.github.io/en/config/transports/xhttp.html
- HY2/Hysteria: https://xtls.github.io/en/config/inbounds/hysteria.html
- REALITY: https://xtls.github.io/en/config/transport.html#realityobject

## 1. HY2 over IPv6 UDP

Fastest path when the VPS IPv6 route is good and the client network allows UDP.

```bash
curl -fsSL https://raw.githubusercontent.com/Boooob626/kokoro-xray/main/install.sh | sudo bash
sudo kokoro-xray edge
sudo kokoro-xray apply
sudo kokoro-xray tune
sudo kokoro-xray link --json hy2 --host auto6 | jq .
```

Open the HY2 UDP port in the VPS firewall too. Default is `443/udp`.

## 2. TLS XHTTP with multi-port jump

Best TCP fallback when UDP is poor or TLS/CDN cover matters.

```bash
sudo jq '.inbound.mode = "tls" | .inbound.tls.ports = [443, 8443, 2053, 2083]' /root/.kokoro-xray/config.json > /tmp/kokoro.json
sudo mv /tmp/kokoro.json /root/.kokoro-xray/config.json
sudo kokoro-xray apply
sudo kokoro-xray tune
sudo kokoro-xray link --json tls | jq .
```

Open every configured TCP port in the VPS security group.

## 3. REALITY XHTTP

Domainless TCP fallback when you do not want your own TLS domain.

```bash
sudo kokoro-xray reality scan --apply
sudo jq '.inbound.mode = "reality"' /root/.kokoro-xray/config.json > /tmp/kokoro.json
sudo mv /tmp/kokoro.json /root/.kokoro-xray/config.json
sudo kokoro-xray apply
sudo kokoro-xray tune
sudo kokoro-xray link
```

## Keep It Small

Skip panel, database, Telegram bot, Docker WARP, Nginx stack, mKCP, and
kitchen-sink protocol support. Add at most one of these later, only when a real
usage test proves the current three paths fail:

```text
traffic: Xray API stats summary, if quota/usage accounting matters
sub: subscription export, if raw JSON stops being enough
snapshot export/import: config + secrets backup, before any database
```
