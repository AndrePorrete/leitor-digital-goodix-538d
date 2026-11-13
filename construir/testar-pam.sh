#!/usr/bin/env bash
# Tests the PAM setup and its undo of instalar.sh inside throwaway containers of each family.
# Usage: construir/testar-pam.sh [image...]     (podman or docker; images without docker.io/ get it)
set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)
ENGINE=$(command -v podman || command -v docker)
read -r -d '' TESTE <<'SH'
set -u
{ if command -v apt-get; then apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq libpam-fprintd libpam-runtime
  elif command -v dnf; then dnf install -y -q fprintd-pam authselect diffutils && { authselect select local --force || authselect select sssd --force; }
  elif command -v pacman; then pacman -Syu --noconfirm --needed fprintd sudo polkit diffutils
  elif command -v zypper; then zypper -n -q install fprintd-pam pam-config tar diffutils; fi; } >/dev/null 2>&1
tar -cf /antes.tar -C / etc/pam.d
FPRINT538D_SO_FUNCOES=1 . /repo/instalar.sh
L=en; detectar_distro; ESTADO=/var/lib/fprint-538d
echo "family=$FAMILIA module=$(modulo_pam_fprintd)"
if [ "$FAMILIA" = debian ]; then
  # version 0.1.0 state: own profile enabled over a backup of the original PAM files
  mkdir -p $ESTADO/backup; tar -cf $ESTADO/backup/pam.tar -C / etc/pam.d var/lib/pam
  printf 'Name: x\nDefault: yes\nPriority: 260\nAuth-Type: Primary\nAuth:\n\t[success=end default=ignore]\tpam_fprintd.so max-tries=3 timeout=20\n' >$LEGADO_PERFIL
  DEBIAN_FRONTEND=noninteractive pam-auth-update --enable fprint-538d >/dev/null
  echo "PAM_METODO=debian" >$ESTADO/estado
  desfazer_legado >/dev/null
  diff -r <(tar -xOf /antes.tar) <(tar -cf - -C / etc/pam.d | tar -xO) >/dev/null && echo "LEGACY UNDO: identical" || echo "LEGACY UNDO: DIFFERENT"
  rm -rf $ESTADO
fi
configurar_pam
echo "-- pam_fprintd lines now:"; grep -Rn -B1 -A1 pam_fprintd /etc/pam.d | grep -v "^--" | sed 's/^/   /' | head -20
configurar_pam >/dev/null   # repair run: must stay identical
n=$(grep -rh pam_fprintd /etc/pam.d/common-auth /etc/pam.d/sudo /etc/pam.d/system-auth 2>/dev/null | grep -vc '^#')
echo "-- after second run, lines in the main file(s): $n"
desfazer_pam
mkdir /antes && tar -xf /antes.tar -C /antes
if diff -r /antes/etc/pam.d /etc/pam.d >/dev/null; then echo "UNDO: identical to before"; else echo "UNDO: DIFFERENT"; diff -r /antes/etc/pam.d /etc/pam.d | head -20; fi
SH
IMAGENS=${*:-"library/ubuntu:24.04 library/debian:13 library/fedora:44 library/almalinux:9 library/archlinux:latest opensuse/tumbleweed opensuse/leap:15.6 ghcr.io/ublue-os/bazzite:stable"}
for img in $IMAGENS; do
  case "$img" in */*/*) ;; *) img=docker.io/$img ;; esac
  echo "===== $img"
  "$ENGINE" run --rm -v "$REPO:/repo:ro,z" "$img" bash -c "$TESTE" 2>&1
done
