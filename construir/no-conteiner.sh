#!/usr/bin/env bash
# Builds the bundle with podman (or docker) in ubuntu:22.04, without touching the host.
# Usage: construir/no-conteiner.sh      -> dist/fprint-538d-x86_64.tar.gz
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
ENGINE=$(command -v podman || command -v docker) || { echo "podman or docker required"; exit 1; }
CACHE=${XDG_CACHE_HOME:-$HOME/.cache}/fprint-538d-build
mkdir -p "$CACHE" "$REPO/dist"
"$ENGINE" run --rm --pull=missing \
  -v "$REPO:/repo:ro,z" -v "$REPO/dist:/out:z" -v "$CACHE:/var/tmp/fprint-538d-build:z" \
  -e OUT=/out docker.io/library/ubuntu:22.04 bash /repo/construir/construir.sh
