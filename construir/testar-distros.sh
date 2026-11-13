#!/usr/bin/env bash
# Checks, in throwaway containers, that the bundle loads and that instalar.sh recognises each
# distribution (family, immutable system, distribution fprintd and PAM module found).
# Usage: construir/testar-distros.sh [bundle.tar.gz | /opt/fprint-538d] [image...]
#   default bundle: dist/fprint-538d-x86_64.tar.gz; default images: the list below.
set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)
ENGINE=$(command -v podman || command -v docker) || { echo "podman or docker required"; exit 1; }
PACOTE=${1:-$REPO/dist/fprint-538d-x86_64.tar.gz}
shift || true
TMP=$(mktemp -d "${TMPDIR:-/tmp}/fprint-538d-distros.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
if [ -d "$PACOTE" ]; then tar -czf "$TMP/pacote.tar.gz" -C "$(dirname "$PACOTE")" "$(basename "$PACOTE")"
else cp "$PACOTE" "$TMP/pacote.tar.gz"; fi

# image  [ostree = image of an atomic system: packages come with it, /run/ostree-booted simulated]
IMAGENS=${*:-"
docker.io/library/ubuntu:22.04
docker.io/library/ubuntu:24.04
docker.io/library/ubuntu:26.04
docker.io/library/debian:12
docker.io/library/debian:13
docker.io/linuxmintd/mint22-amd64
docker.io/library/fedora:42
docker.io/library/fedora:43
docker.io/library/fedora:44
docker.io/library/almalinux:9
docker.io/library/almalinux:10
docker.io/library/archlinux:latest
docker.io/manjarolinux/base:latest
docker.io/cachyos/cachyos:latest
docker.io/opensuse/tumbleweed
docker.io/opensuse/leap:15.6
docker.io/opensuse/leap:16.0
ghcr.io/ublue-os/bazzite:stable:ostree
quay.io/fedora-ostree-desktops/kinoite:43:ostree
"}

read -r -d '' TESTE <<'SH'
set -u
if [ "${OSTREE:-0}" = 1 ]; then mkdir -p /run && touch /run/ostree-booted
else
  { if command -v apt-get; then apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq fprintd libpam-fprintd
    elif command -v dnf; then dnf install -y -q fprintd fprintd-pam
    elif command -v pacman; then pacman -Syu --noconfirm --needed fprintd
    elif command -v zypper; then zypper -n -q install fprintd fprintd-pam tar gzip; fi; } >/dev/null 2>&1
fi
command -v tar >/dev/null || { echo "RESULT FAIL no tar"; exit 1; }
cd /tmp && tar -xzf /pacote.tar.gz
falta=$(ldd fprint-538d/libexec/fprintd fprint-538d/lib/libfprint-2.so.2 2>&1 | grep -i 'not found' | sort -u | tr -s ' \t' ' ')
carga=FAIL; LD_BIND_NOW=1 fprint-538d/libexec/fprintd --help >/dev/null 2>&1 && carga=OK
FPRINT538D_SO_FUNCOES=1 . /repo/instalar.sh
L=pt; detectar_distro
pac=no; pacotes_distro_ok && pac=yes
glibc=$(glibc_ok && echo ok || echo old)
echo "RESULT load=$carga family=$FAMILIA immutable=$IMUTAVEL distro_fprintd=$pac glibc=$glibc pam=$(modulo_pam_fprintd || echo none) ${falta:+missing:$falta} | $NOME_DISTRO"
SH

for linha in $IMAGENS; do
  img=$linha ostree=0
  case "$linha" in *:ostree) img=${linha%:ostree}; ostree=1 ;; esac
  printf '%-48s ' "$img"
  "$ENGINE" run --rm --pull=missing -e OSTREE=$ostree -v "$REPO:/repo:ro,z" -v "$TMP/pacote.tar.gz:/pacote.tar.gz:ro,z" \
    "$img" bash -c "$TESTE" 2>&1 | grep -E '^RESULT|Error|error:' | tail -1 | sed 's/^RESULT //'
done
