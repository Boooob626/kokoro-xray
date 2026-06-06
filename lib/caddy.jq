# kokoro-xray Caddyfile renderer
# Usage: jq -r -f caddy.jq --slurpfile cfg config.json --slurpfile sec secrets.json

def cfg: $cfg[0];
def sec: $sec[0];

def sni: cfg.inbound.reality.server_names[0];
def cdn: cfg.inbound.tls.cdn_domain;
def path: sec.inbound.xhttp_path;
def email: if cfg.inbound.tls.acme_email != "" then cfg.inbound.tls.acme_email else "admin@\(.cdn)" end;

def l4_block: if cfg.caddy.use_l4 then "    servers {\n        layer4\n    }\n" else "" end;

def port443_block: if cfg.caddy.use_l4 then
  "
:443 {
    @reality tls sni \(sni)
    handle @reality {
        proxy 127.0.0.1:8443
    }
    @cdn tls sni \(cdn)
    handle @cdn {
        tls
        reverse_proxy 127.0.0.1:8444 {
            transport http {
                versions h2c
            }
        }
    }
}
"
else
  "
:443 {
    tls
    reverse_proxy 127.0.0.1:8444 {
        transport http {
            versions h2c
        }
    }
}
"
end;

"{
\(l4_block)    email \(email)
}
\(port443_block)
\(cdn) {
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

:80 {
    redir https://{host}{uri} permanent
}
"