#!/usr/bin/env bash
# kokoro-xray — exit node (NL) setup

source "$(cd -P -- "$(dirname -- "$0")/../lib" && pwd -P)/common.sh"
source "$(kokoro_project_root)/lib/os.sh"
source "$(kokoro_project_root)/lib/xray.sh"
source "$(kokoro_project_root)/lib/keys.sh"
source "$(kokoro_project_root)/lib/render.sh"
source "$(kokoro_project_root)/lib/validate.sh"

kokoro_exit_install() {
    kokoro_need_root
    kokoro_ensure_config
    kokoro_cfg_set_str '.role' 'exit'

    kokoro_install_deps
    kokoro_xray_install
    kokoro_gen_exit_secrets
    kokoro_build_exit_xray
    kokoro_validate
    kokoro_xray_restart

    kokoro_log "exit node ready"
    kokoro_log "paste into edge multinode.exit_pubkey: $(kokoro_cfg '.multinode.local_pubkey')"
    kokoro_log "open UDP $(kokoro_cfg '.multinode.exit_port') on firewall"
}

kokoro_exit_install