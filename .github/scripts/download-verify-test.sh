#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="/tmp/kokoro-download-verify-test"
rm -rf "$OUT"
mkdir -p "$OUT"

export KOKORO_ROOT="$ROOT"
source "${ROOT}/lib/geodata.sh"

printf 'kokoro-test-zip\n' >"${OUT}/test.zip"
sha="$(sha256sum "${OUT}/test.zip" | awk '{print $1}')"

cat >"${OUT}/test.zip.dgst" <<EOF
MD5= unused
SHA2-256= ${sha}
EOF

kokoro_xray_verify_zip "${OUT}/test.zip" "${OUT}/test.zip.dgst"
echo "checksum_ok OK"

cat >"${OUT}/bad.zip.dgst" <<'EOF'
SHA2-256= 0000000000000000000000000000000000000000000000000000000000000000
EOF

if (kokoro_xray_verify_zip "${OUT}/test.zip" "${OUT}/bad.zip.dgst" >/dev/null 2>&1); then
    echo "bad checksum unexpectedly passed" >&2
    exit 1
fi

echo "checksum_bad OK"
echo "download-verify-test OK"
