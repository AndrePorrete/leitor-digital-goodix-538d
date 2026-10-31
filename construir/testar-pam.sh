#!/usr/bin/env bash
# Tests the PAM setup and its undo of instalar.sh inside throwaway containers of each family.
# Usage: construir/testar-pam.sh      (podman or docker)
set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)
ENGINE=$(command -v podman || command -v docker)
read -r -d '' TESTE <<'SH'
set -u
{ if command -v apt-get; then apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq libpam-fprintd libpam-runtime
  elif command -v dnf; then dnf install -y -q fprintd-pam authselect diffutils && authselect select local --force
  elif command -v pacman; then pacman -Sy --noconfirm --needed fprintd sudo polkit diffutils
  elif command -v zypper; then zypper -n -q install fprintd-pam pam-config tar diffutils; fi; } >/dev/null 2>&1
tar -cf /antes.tar -C / etc/pam.d
FPRINT538D_SO_FUNCOES=1 . /repo/instalar.sh
L=en; detectar_distro; ESTADO=/var/lib/fprint-538d
echo "family=$FAMILIA module=$(modulo_pam_fprintd)"
configurar_pam
echo "-- pam_fprintd lines now:"; grep -Rn -B1 -A1 pam_fprintd /etc/pam.d | grep -v "^--" | sed 's/^/   /' | head -20
for i in 1; do configurar_pam >/dev/null; done   # repair run: must stay identical
n=$(grep -rh pam_fprintd /etc/pam.d/common-auth /etc/pam.d/sudo /etc/pam.d/system-auth 2>/dev/null | grep -vc '^#')
echo "-- after second run, lines in the main file(s): $n"
desfazer_pam
mkdir /antes && tar -xf /antes.tar -C /antes
if diff -r /antes/etc/pam.d /etc/pam.d >/dev/null; then echo "UNDO: identical to before"; else echo "UNDO: DIFFERENT"; diff -r /antes/etc/pam.d /etc/pam.d | head -20; fi
SH
for img in library/ubuntu:24.04 library/debian:12 library/fedora:41 library/archlinux:latest opensuse/tumbleweed opensuse/leap:15.6; do
  echo "===== $img"
  "$ENGINE" run --rm -v "$REPO:/repo:ro,z" "docker.io/$img" bash -c "$TESTE" 2>&1
done
