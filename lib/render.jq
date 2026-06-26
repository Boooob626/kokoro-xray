# kokoro-xray declarative xray config renderer
# Usage: jq -f render.jq --slurpfile cfg config.json --slurpfile sec secrets.json

def cfg: $cfg[0];
def sec: $sec[0];
def mode: cfg.inbound.mode;
def role: cfg.role;
def hy2_enabled: cfg.inbound.hy2.enabled // false;

def log_block: { log: { loglevel: "warning" } };

def policy_block: {
  policy: { levels: { "0": { handshake: 2, connIdle: 120 } } }
};

def reality_listen: if mode == "reality" then "0.0.0.0" else "127.0.0.1" end;
def reality_port: if mode == "reality" then 443 else 8443 end;
def xhttp_sockopt: { trustedXForwardedFor: ["Kokoro-Trusted-XFF"] };
def xhttp_base_settings: { path: sec.inbound.xhttp_path };
def xhttp_tls_settings: xhttp_base_settings + {
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
};

def reality_inbound: {
  tag: "REALITY_XHTTP_IN",
  listen: reality_listen,
  port: reality_port,
  protocol: "vless",
  settings: {
    clients: [{ id: sec.inbound.uuid, flow: "" }],
    decryption: "none"
  },
  streamSettings: {
    network: "xhttp",
    security: "reality",
    realitySettings: {
      show: false,
      dest: cfg.inbound.reality.dest,
      xver: 0,
      serverNames: cfg.inbound.reality.server_names,
      privateKey: sec.inbound.reality.private_key,
      shortIds: sec.inbound.reality.short_ids
    },
    xhttpSettings: xhttp_base_settings,
    sockopt: xhttp_sockopt
  },
  sniffing: { enabled: true, destOverride: ["http", "tls", "quic"] }
};

def tls_inbound: {
  tag: "TLS_XHTTP_IN",
  listen: "127.0.0.1",
  port: 8444,
  protocol: "vless",
  settings: {
    clients: [{ id: sec.inbound.uuid, flow: "" }],
    decryption: "none"
  },
  streamSettings: {
    network: "xhttp",
    security: "none",
    xhttpSettings: xhttp_tls_settings,
    sockopt: xhttp_sockopt
  },
  sniffing: { enabled: true, destOverride: ["http", "tls", "quic"] }
};

def hy2_sni:
  if (cfg.inbound.hy2.sni // "") != "" then cfg.inbound.hy2.sni
  elif (cfg.inbound.tls.domain // "") != "" then cfg.inbound.tls.domain
  else "kokoro-hy2.local" end;

def hy2_inbound: {
  tag: "HY2_IN",
  listen: "::",
  port: cfg.inbound.hy2.port,
  protocol: "hysteria",
  settings: {
    version: 2,
    users: [{
      auth: sec.inbound.hy2.auth,
      level: 0,
      email: "kokoro-hy2"
    }]
  },
  streamSettings: {
    network: "hysteria",
    security: "tls",
    tlsSettings: {
      serverName: hy2_sni,
      alpn: ["h3"],
      certificates: [{
        certificateFile: cfg.paths.hy2_cert,
        keyFile: cfg.paths.hy2_key
      }]
    },
    hysteriaSettings: {
      version: 2,
      auth: sec.inbound.hy2.auth,
      udpIdleTimeout: 60,
      masquerade: {
        type: "proxy",
        url: cfg.inbound.hy2.masquerade,
        rewriteHost: true,
        insecure: false
      }
    }
  },
  sniffing: { enabled: true, destOverride: ["http", "tls", "quic"] }
};

def base_outbounds: [
  { tag: "DIRECT", protocol: "freedom" },
  { tag: "BLOCK", protocol: "blackhole" }
];

def wg_outbound: if cfg.multinode.enabled then
  [{
    tag: "WG_TO_EXIT",
    protocol: "wireguard",
    settings: {
      secretKey: sec.multinode.edge_wg_privkey,
      address: ["\((cfg.multinode.local_wg_ip))/32"],
      peers: [{
        publicKey: cfg.multinode.peer_exit_pubkey,
        endpoint: "\(cfg.multinode.exit_ip):\(cfg.multinode.exit_port)",
        allowedIPs: ["0.0.0.0/0", "::/0"]
      }]
    }
  }]
else [] end;

# Single-node: allow Google (incl. .cn) before CN/RU blocks
def google_direct_rules: [
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
    outboundTag: "DIRECT"
  }
];

def single_node_block_rules: [
  { type: "field", ip: ["geoip:private"], outboundTag: "BLOCK" },
  { type: "field", domain: ["geosite:private"], outboundTag: "BLOCK" },
  { type: "field", protocol: ["bittorrent"], outboundTag: "BLOCK" },
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
  { type: "field", ip: ["geoip:cn"], outboundTag: "BLOCK" },
  { type: "field", ip: ["geoip:ru"], outboundTag: "BLOCK" }
];

def edge_single_routing: {
  domainStrategy: "IPIfNonMatch",
  rules: (google_direct_rules + single_node_block_rules + [
    { type: "field", network: "tcp,udp", outboundTag: "DIRECT" }
  ])
};

def edge_multinode_routing: {
  domainStrategy: "IPIfNonMatch",
  rules: [
    { type: "field", network: "tcp,udp", outboundTag: "WG_TO_EXIT" }
  ]
};

def edge_routing: if cfg.multinode.enabled then edge_multinode_routing else edge_single_routing end;

def edge_inbounds:
  (if mode == "reality" then [reality_inbound] else [] end)
  + (if mode == "tls" then [tls_inbound] else [] end)
  + (if hy2_enabled then [hy2_inbound] else [] end);

def edge_config: log_block + {
  inbounds: edge_inbounds,
  outbounds: (base_outbounds + wg_outbound),
  routing: edge_routing,
  policy: policy_block.policy
};

def exit_inbound: {
  tag: "WG_EXIT_IN",
  listen: "0.0.0.0",
  port: cfg.multinode.exit_port,
  protocol: "wireguard",
  settings: {
    secretKey: sec.multinode.exit_wg_privkey,
    mtu: 1420,
    peers: [{
      publicKey: cfg.multinode.peer_edge_pubkey,
      allowedIPs: ["\((cfg.multinode.peer_wg_ip))/32"]
    }]
  }
};

def exit_config: log_block + {
  inbounds: [exit_inbound],
  outbounds: base_outbounds,
  routing: {
    domainStrategy: "IPIfNonMatch",
    rules: [
      { type: "field", ip: ["geoip:private"], outboundTag: "BLOCK" },
      { type: "field", protocol: ["bittorrent"], outboundTag: "BLOCK" },
      { type: "field", network: "tcp,udp", outboundTag: "DIRECT" }
    ]
  },
  policy: policy_block.policy
};

if role == "edge" then edge_config
elif role == "exit" then exit_config
else error("unknown role: \(role)")
end
