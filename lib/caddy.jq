# kokoro-xray Caddyfile renderer
# Usage: jq -r -f caddy.jq --slurpfile cfg config.json --slurpfile sec secrets.json

def cfg: $cfg[0];
def sec: $sec[0];

def sni: cfg.inbound.reality.server_names[0];
def cdn: cfg.inbound.tls.cdn_domain;
def path: sec.inbound.xhttp_path;
def email: if cfg.inbound.tls.acme_email != "" then cfg.inbound.tls.acme_email else "admin@\(.cdn)" end;
def xhttp_socket: cfg.inbound.xhttp.socket // true;
def xhttp_socket_path: cfg.inbound.xhttp.socket_path // "/run/kokoro-xray/xhttp.sock";
def fallback_root: cfg.fallback.root // "/var/www/kokoro-fallback";
def fallback_proxy_url: cfg.fallback.proxy_url // "";
def xhttp_upstream: if xhttp_socket then
  "unix//\(xhttp_socket_path)"
else
  "127.0.0.1:8444"
end;
def fallback_type: cfg.fallback.type // "static";
def fallback_block:
  if fallback_type == "static" then
    "    handle {\n        root * \(fallback_root)\n        file_server\n    }"
  elif fallback_type == "proxy" then
    "    handle {\n        reverse_proxy \(fallback_proxy_url) {\n            header_up Host {upstream_hostport}\n        }\n    }"
  else
    "    handle {\n        respond \"ok\" 200\n    }"
  end;

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

"{
\(l4_block)    email \(email)
}
\(cdn) {
    handle \(path)* {
        reverse_proxy \(xhttp_upstream) {
            transport http {
                versions h2c
            }
        }
    }
\(fallback_block)
}

:80 {
    redir https://{host}{uri} permanent
}
"
