#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

heavy="$(git -C "${ROOT}" ls-files | grep -E '(^|/)prebuilt/|\.dat$|/xray$|\.tar(\.|$)|\.zip$|\.gz$|\.xz$|\.zst$|\.bin$|\.deb$|\.rpm$' || true)"
if [ -n "${heavy}" ]; then
    echo "tracked heavy runtime assets:" >&2
    echo "${heavy}" >&2
    exit 1
fi

for lib in apply caddy health keys os preflight reload render snapshot validate xray; do
    bash -c "source '${ROOT}/lib/${lib}.sh'" "${ROOT}/roles/edge.sh"
done

echo "source-path-test OK"
