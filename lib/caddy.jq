# kokoro-xray Caddyfile renderer
# Usage: jq -r -f caddy.jq --slurpfile cfg config.json --slurpfile sec secrets.json

def cfg: $cfg[0];
def sec: $sec[0];

def sni: cfg.inbound.reality.server_names[0];
def cdn: cfg.inbound.tls.cdn_domain;
def path: sec.inbound.xhttp_path;
def email: if cfg.inbound.tls.acme_email != "" then cfg.inbound.tls.acme_email else "admin@\(.cdn)" end;
def tls_ports: [(cfg.inbound.tls.ports // [443])[] | tonumber] | unique;

def l4_block: if cfg.caddy.use_l4 and cfg.inbound.mode == "both" then
  "
    servers :443 {
        listener_wrappers {
            layer4 {
                @reality tls sni \(sni)
                route @reality {
                    proxy tcp/127.0.0.1:8443
                }
            }
            tls
        }
    }
"
else "" end;

def tls_addr($port): if $port == 443 then cdn else "\(cdn):\($port)" end;
def tls_site($port): "\(tls_addr($port)) {
    handle \(path)* {
        reverse_proxy 127.0.0.1:8444 {
            transport http {
                versions h2c
            }
        }
    }
    handle {
        respond \"ok\" 200
    }
}
";

"{
\(l4_block)    email \(email)
}
\(tls_ports | map(tls_site(.)) | join("\n"))

:80 {
    redir https://{host}{uri} permanent
}
"
