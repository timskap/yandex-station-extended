#!/usr/bin/env bash
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUTPUT=${1:-$HERE/../packages/airplay-lite-5.6.2.tar.gz}
IMAGE=mikebrady/shairport-sync@sha256:b6192daba080e2511716490fa104a0bf96ebbb6dbf49d42a39243d9d6c5f97f9
BUILDER=alpine@sha256:5b10f432ef3da1b8d4c7eb6c487f2f5a8f096bc91145e68878dd4a5019afde11
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cp "$HERE/extract-runtime.sh" "$WORK/"
cp "$HERE/device/airplay-buttons.c" "$WORK/"
docker run --rm --platform linux/arm64 --network none --user 0 --entrypoint /bin/sh \
  -v "$WORK:/out" "$IMAGE" /out/extract-runtime.sh
docker run --rm --platform linux/arm64 --user 0 -v "$WORK:/out" "$BUILDER" sh -c '
  set -e
  apk add --no-cache gcc=15.2.0-r2 musl-dev=1.2.5-r24 linux-headers=6.16.12-r0 alsa-lib-dev=1.2.14-r2
  cc -std=c11 -D_GNU_SOURCE -Wall -Wextra -Werror -Os -s /out/airplay-buttons.c \
    -o /out/runtime/bin/airplay-buttons -lasound -lm
'
python3 "$HERE/bundle.py" pack --runtime "$WORK/runtime" --output "$OUTPUT"
