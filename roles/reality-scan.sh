#!/usr/bin/env bash
# kokoro-xray — reality scan entry

export KOKORO_ROOT="$(cd -P -- "$(dirname -- "$0")/.." && pwd -P)"
source "${KOKORO_ROOT}/lib/reality-scan.sh"
kokoro_reality_scan "$@"