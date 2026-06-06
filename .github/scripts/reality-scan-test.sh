#!/usr/bin/env bash
# Unit-style test for reality scan (blocked names + normalize)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export KOKORO_ROOT="$ROOT"
source "${ROOT}/lib/reality-scan.sh"

test_blocked() {
    kokoro_reality_blocked "www.apple.com" && echo "block apple OK"
    kokoro_reality_blocked "gateway.icloud.com" && echo "block icloud OK"
    ! kokoro_reality_blocked "www.sky.com" && echo "allow sky OK"
}

test_normalize() {
    [[ "$(kokoro_reality_normalize_host 'https://www.sky.com/path')" == "www.sky.com" ]]
    echo "normalize OK"
}

test_blocked
test_normalize

# Live probe (optional, needs network)
if [[ "${KOKORO_LIVE_SCAN:-}" == "1" ]]; then
    out="$(kokoro_reality_validate_one github.com)"
    echo "$out" | grep -q '^OK' && echo "live debian OK" || { echo "live fail: $out"; exit 1; }
fi

echo "reality-scan-test OK"