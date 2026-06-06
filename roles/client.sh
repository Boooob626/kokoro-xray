#!/usr/bin/env bash
# kokoro-xray — share link + QR entry

export KOKORO_ROOT="$(cd -P -- "$(dirname -- "$0")/.." && pwd -P)"
source "${KOKORO_ROOT}/lib/link.sh"
kokoro_link_show "$@"