#!/usr/bin/env bash
# fprint-538d — fingerprint reader Goodix 27c6:538d on Linux (Dell Inspiron 5590, 5402, 5409, 3501,
# 7506, Latitude 3410, Vostro 3500...). Installs a patched fprintd + libfprint in /opt/fprint-538d,
# next to the distribution packages (nothing of the distribution is overwritten).
#
#   Install / repair / update:  bash instalar.sh
#   After installing:           "Fingerprint reader" in the applications menu, or: leitor-digital
#                               (enroll, test, recognition level, update, uninstall)
#   Uninstall:                  bash instalar.sh --desinstalar      (or --uninstall)
#   Recognition level:          bash instalar.sh --ajustar          (or --tune)
#   Options:                    --nivel rigoroso|padrao|tolerante  recognition level without asking
#                                 (also strict|default|tolerant; works with install and --ajustar)
#                               --pacote FILE.tar.gz   use a local bundle instead of downloading
#                               --compilar             build the bundle here (podman or docker)
#                               --sem-cadastro         do not enroll a finger at the end
#                               --sim                  answer every question with the default
#                               --lang pt|en
# Run as your normal user (not with sudo): the password is asked once, for the system part.
# Project: https://github.com/AndrePorrete/leitor-digital-goodix-538d — License: GPL-2.0-or-later
set -uo pipefail

REPO_GH=AndrePorrete/leitor-digital-goodix-538d
URL_PACOTE=https://github.com/$REPO_GH/releases/latest/download/fprint-538d-x86_64.tar.gz
PREFIXO=/opt/fprint-538d
ESTADO=/var/lib/fprint-538d
DROPIN_DIR=/etc/systemd/system/fprintd.service.d
DROPIN=$DROPIN_DIR/fprint-538d.conf
ATALHO_BIN=/usr/local/bin/leitor-digital
ATALHO_DESKTOP=/usr/local/share/applications/fprint-538d.desktop
TOQUES=15 # enrollment stages of the driver
AJUSTE_CONF=/etc/fprint-538d.conf # recognition level, kept on update
# Acceptance threshold levels (score 0-100). Wrong fingers scored at most 51 in the tests.
NIVEIS=(70 60 55)
NIVEL_PADRAO=60
DROPINS_ANTIGOS="goodix-538d.conf calibracao.conf" # manual install of the first version
# Left by version 0.1.0 (own PAM profile / lines, power button): removed on update and uninstall
LEGADO_LOGIND=/etc/systemd/logind.conf.d/fprint-538d-botao.conf
LEGADO_PERFIL=/usr/share/pam-configs/fprint-538d
LEGADO_MARCA="# fprint-538d"
LEGADO_PAM_ARQUIVOS="sudo polkit-1 system-local-login"
USB_VENDOR=27c6
USB_PRODUCT=538d

# ---------------------------------------------------------------------------------------------
# Messages (Portuguese / English)

L=en
case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in pt*) L=pt ;; esac
t() { if [ "$L" = pt ]; then printf '%s' "$1"; else printf '%s' "$2"; fi; }

if [ -t 1 ]; then C_AZ=$'\033[1;36m' C_VD=$'\033[1;32m' C_AM=$'\033[1;33m' C_VM=$'\033[1;31m' C_N=$'\033[1m' C_CZ=$'\033[2m' C_0=$'\033[0m'
else C_AZ='' C_VD='' C_AM='' C_VM='' C_N='' C_CZ='' C_0=''; fi
LOG=""
log() { [ -z "$LOG" ] || printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$LOG" 2>/dev/null || true; }
titulo() { printf '\n%s== %s%s\n' "$C_AZ" "$(t "$1" "$2")" "$C_0"; log "== $2"; }
PASSOS=5
passo() { # n "pt" "en"
  printf '\n%s━━ %s %d %s %d — %s%s\n' "$C_AZ" "$(t Passo Step)" "$1" "$(t de of)" "$PASSOS" "$(t "$2" "$3")" "$C_0"
  log "== step $1: $3"
}
info() { printf '   %s\n' "$(t "$1" "$2")"; log "   $2"; }
ok() { printf '   %s✔%s %s\n' "$C_VD" "$C_0" "$(t "$1" "$2")"; log "OK $2"; }
aviso() { printf '   %s!%s %s\n' "$C_AM" "$C_0" "$(t "$1" "$2")"; log "WARN $2"; }
erro() { printf '\n   %s✘ %s%s\n' "$C_VM" "$(t "$1" "$2")" "$C_0" >&2; log "ERROR $2"; }
fim_erro() { # pt en
  erro "$1" "$2"
  printf '   %s\n\n' "$(t "Nada foi alterado no sistema além do que foi dito acima. Dúvidas: https://github.com/$REPO_GH/issues" \
    "Nothing was changed in the system beyond what is shown above. Help: https://github.com/$REPO_GH/issues")" >&2
  exit 1
}

SIM=0
TEM_TTY=0
{ exec 3</dev/tty; } 2>/dev/null && TEM_TTY=1
# perguntar "pergunta" "question" s|n -> returns 0 for yes
perguntar() {
  local padrao=$3 resp opcoes
  if [ "$padrao" = s ]; then opcoes=$(t "[Enter = Sim · n = Não]" "[Enter = Yes · n = No]")
  else opcoes=$(t "[Enter = Não · s = Sim]" "[Enter = No · y = Yes]"); fi
  if [ "$SIM" = 1 ] || [ "$TEM_TTY" = 0 ]; then
    printf '   %s %s %s\n' "$(t "$1" "$2")" "$opcoes" "$padrao"
    [ "$padrao" = s ]; return
  fi
  while true; do
    printf '   %s%s%s %s ' "$C_N" "$(t "$1" "$2")" "$C_0" "$opcoes"
    read -r resp <&3 || resp=""
    resp=${resp,,}
    [ -z "$resp" ] && resp=$padrao
    case "$resp" in s | sim | y | yes) return 0 ;; n | nao | não | no) return 1 ;; esac
  done
}
# Animated wait line (spinner + seconds) for anything slower than a moment; output goes to the log.
# Returns the command status; the caller prints the result.
esperar() { # "pt" "en" command...
  local msg pid i=0 ini=$SECONDS marcas='|/-\'
  msg=$(t "$1" "$2"); shift 2
  log "run: $*"
  "$@" >>"${LOG:-/dev/null}" 2>&1 </dev/null &
  pid=$!
  if [ -t 1 ]; then
    while kill -0 "$pid" 2>/dev/null; do
      printf '\r   %s %s %s(%ds — %s)%s ' "${marcas:$((i++ % 4)):1}" "$msg" "$C_CZ" $((SECONDS - ini)) "$(t "aguarde, está funcionando" "please wait, it is working")" "$C_0"
      sleep 0.25
    done
    printf '\r\033[K'
  else
    printf '   ... %s\n' "$msg"
  fi
  wait "$pid"
}
mostrar_log() { [ -r "$LOG" ] && { printf '%s' "$C_CZ"; tail -n 6 "$LOG" | sed 's/^/      /'; printf '%s   %s %s\n' "$C_0" "$(t "Registro completo:" "Full log:")" "$LOG"; }; }

esperar_enter() {
  [ "$SIM" = 1 ] || [ "$TEM_TTY" = 0 ] && return 0
  printf '   %s%s%s ' "$C_N" "$(t "$1" "$2")" "$C_0"
  read -r _ <&3 || true
}

# ---------------------------------------------------------------------------------------------
# System detection

FAMILIA=desconhecida IMUTAVEL=0 NOME_DISTRO="Linux"
detectar_distro() {
  local ids
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    NOME_DISTRO=${PRETTY_NAME:-${NAME:-Linux}}
    ids=" ${ID:-} ${ID_LIKE:-} "
    case "$ids" in
      *" debian "* | *" ubuntu "*) FAMILIA=debian ;;
      *" fedora "* | *" rhel "* | *" centos "*) FAMILIA=fedora ;;
      *" arch "* | *" archlinux "*) FAMILIA=arch ;;
      *suse*) FAMILIA=suse ;;
    esac
  fi
  if [ -e /run/ostree-booted ]; then IMUTAVEL=ostree
  elif [ "$FAMILIA" = suse ] && command -v transactional-update >/dev/null 2>&1; then IMUTAVEL=transactional
  fi
}

sensor_presente() {
  local d
  for d in /sys/bus/usb/devices/*; do
    [ -r "$d/idVendor" ] || continue
    [ "$(cat "$d/idVendor")" = "$USB_VENDOR" ] && [ "$(cat "$d/idProduct")" = "$USB_PRODUCT" ] && return 0
  done
  return 1
}

modelo() { cat /sys/class/dmi/id/product_name 2>/dev/null || echo "?"; }
# The bundle is built on glibc 2.35 but needs only GLIBC_2.33 symbols (RHEL/Alma/Rocky 9 included)
GLIBC_MIN=2.33
glibc_ok() { # false only when the C library is known to be too old or not glibc (musl)
  local v
  v=$(getconf GNU_LIBC_VERSION 2>/dev/null) || v=$(ldd --version 2>&1 | head -n 1)
  case "$v" in
    *musl*) return 1 ;;
    *GNU*libc* | glibc*) v=${v##* } ;;
    *) return 0 ;;
  esac
  [ "$(printf '%s\n%s\n' "$GLIBC_MIN" "$v" | sort -V | head -n 1)" = "$GLIBC_MIN" ]
}

modulo_pam_fprintd() {
  local f
  for f in /usr/lib64/security /lib64/security /usr/lib/security /lib/security /usr/lib/x86_64-linux-gnu/security /lib/x86_64-linux-gnu/security; do
    [ -e "$f/pam_fprintd.so" ] && { echo "$f/pam_fprintd.so"; return 0; }
  done
  return 1
}
servico_fprintd() {
  local d
  for d in /usr/lib/systemd/system /lib/systemd/system /etc/systemd/system; do
    [ -e "$d/fprintd.service" ] && return 0
  done
  return 1
}
pacotes_distro_ok() { servico_fprintd && modulo_pam_fprintd >/dev/null && command -v fprintd-enroll >/dev/null; }

# libfprint replaced by other guides: scripts that build a libfprint fork and "ninja install" it over
# the distribution's library (prefix /usr) or next to it (/usr/local). Our bundle has its own copy
# (RUNPATH), so it is not affected, but the system is left with a foreign driver: put the original back.
LIBFPRINT_LOCAL_GLOB="/usr/local/lib/libfprint-2.so* /usr/local/lib64/libfprint-2.so* /usr/local/lib/x86_64-linux-gnu/libfprint-2.so*"
pacote_libfprint() { # distribution package that owns libfprint-2.so.2
  local f
  for f in /usr/lib/x86_64-linux-gnu/libfprint-2.so.2 /usr/lib64/libfprint-2.so.2 /usr/lib/libfprint-2.so.2; do
    [ -e "$f" ] || continue
    f=$(readlink -f "$f")
    case "$FAMILIA" in
      debian) dpkg-query -S "$f" 2>/dev/null | sed -n '1s/: .*//p' ;;
      fedora | suse) rpm -qf --qf '%{NAME}\n' "$f" 2>/dev/null | grep -v 'not owned' ;;
      arch) pacman -Qqo "$f" 2>/dev/null ;;
    esac
    return 0
  done
  return 1
}
libfprint_alterada() { # prints what was changed; true if something was
  # (rpm -V and pacman -Qkk exit 1 when they find changes: "|| true" keeps pipefail from hiding them)
  local pkg achou=1 f
  pkg=$(pacote_libfprint)
  if [ -n "$pkg" ]; then
    case "$FAMILIA" in
      debian) { LC_ALL=C dpkg --verify "$pkg" 2>/dev/null || true; } | grep -qE '^..5[^ ]* .*libfprint-2\.so' && achou=0 ;;
      fedora | suse) { LC_ALL=C rpm -V "$pkg" 2>/dev/null || true; } | grep -qE '^[^ ]*5[^ ]* .*libfprint-2\.so' && achou=0 ;;
      arch) { LC_ALL=C pacman -Qkk "$pkg" 2>&1 || true; } | grep -i 'libfprint-2\.so' | grep -qiE 'checksum|size' && achou=0 ;;
    esac
    [ $achou = 0 ] && echo "pacote:$pkg"
  fi
  for f in $LIBFPRINT_LOCAL_GLOB; do
    [ -e "$f" ] || [ -L "$f" ] || continue
    echo "local:$f"
    achou=0
  done
  return $achou
}

# ---------------------------------------------------------------------------------------------
# ROOT PART (runs through sudo/pkexec: bash instalar.sh --interno ACTION ...)

estado_set() { # key value
  mkdir -p "$ESTADO"
  touch "$ESTADO/estado"
  sed -i "/^$1=/d" "$ESTADO/estado"
  printf '%s=%q\n' "$1" "$2" >>"$ESTADO/estado"
}
estado_get() { (
  [ -r "$ESTADO/estado" ] || exit 0
  # shellcheck disable=SC1091
  . "$ESTADO/estado"
  eval "printf '%s' \"\${$1:-}\""
); }

instalar_pacotes_distro() {
  pacotes_distro_ok && { ok "fprintd e módulo PAM da distribuição já instalados" "Distribution fprintd and PAM module already installed"; return 0; }
  local msg_pt="Instalando os programas de digital do sistema (1 a 3 minutos)" msg_en="Installing the system fingerprint programs (1 to 3 minutes)"
  case "$FAMILIA:$IMUTAVEL" in
    debian:0) esperar "$msg_pt" "$msg_en" sh -c 'apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq fprintd libpam-fprintd' || return 1 ;;
    fedora:0) esperar "$msg_pt" "$msg_en" dnf install -y -q fprintd fprintd-pam || return 1 ;;
    fedora:ostree | *:ostree)
      esperar "Adicionando os programas de digital ao sistema (alguns minutos)" "Adding the fingerprint programs to the system (a few minutes)" \
        rpm-ostree install --idempotent fprintd fprintd-pam || return 1
      aviso "Pacotes adicionados à imagem do sistema. REINICIE o computador e rode este instalador de novo." \
        "Packages added to the system image. REBOOT the computer and run this installer again."
      exit 3 ;;
    arch:0) esperar "$msg_pt" "$msg_en" pacman -S --needed --noconfirm fprintd || return 1 ;;
    suse:0) esperar "$msg_pt" "$msg_en" zypper -n -q install fprintd fprintd-pam || return 1 ;;
    suse:transactional)
      esperar "$msg_pt" "$msg_en" transactional-update -n pkg install fprintd fprintd-pam || return 1
      aviso "Pacotes instalados num novo instantâneo. REINICIE e rode este instalador de novo." \
        "Packages installed in a new snapshot. REBOOT and run this installer again."
      exit 3 ;;
    *) return 1 ;;
  esac
  pacotes_distro_ok && ok "Programas de digital do sistema instalados" "System fingerprint programs installed"
}

restaurar_libfprint() { # put back the distribution's libfprint changed by another guide
  [ "$IMUTAVEL" = 0 ] || return 0
  local itens item pkg f destino falhou=0
  local msg_pt="Restaurando a biblioteca de digital original do sistema" msg_en="Restoring the system's original fingerprint library"
  itens=$(libfprint_alterada) || return 0
  for item in $itens; do
    case "$item" in
      pacote:*)
        pkg=${item#pacote:}
        log "libfprint of $pkg changed by another installer: reinstalling"
        case "$FAMILIA" in
          debian) esperar "$msg_pt" "$msg_en" sh -c "apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install --reinstall -y -qq '$pkg'" || falhou=1 ;;
          fedora) esperar "$msg_pt" "$msg_en" dnf reinstall -y -q "$pkg" || falhou=1 ;;
          arch) esperar "$msg_pt" "$msg_en" pacman -S --noconfirm "$pkg" || falhou=1 ;;
          suse) esperar "$msg_pt" "$msg_en" zypper -n -q install -f "$pkg" || falhou=1 ;;
        esac
        ;;
      local:*)
        f=${item#local:}
        destino=$ESTADO/backup/libfprint-usr-local$(dirname "$f")
        if mkdir -p "$destino" && mv "$f" "$destino/"; then log "moved $f to $destino (undo: mv back, then ldconfig)"; else falhou=1; fi
        ;;
    esac
  done
  ldconfig 2>/dev/null
  if [ $falhou = 0 ]; then
    ok "Biblioteca de digital do sistema restaurada (estava trocada por outro instalador)" \
      "System fingerprint library restored (it had been replaced by another installer)"
  else
    aviso "Não consegui restaurar toda a biblioteca de digital do sistema; o driver deste instalador funciona mesmo assim." \
      "Could not fully restore the system fingerprint library; this installer's driver works anyway."
  fi
  return 0
}

# SELinux (Fedora, openSUSE Tumbleweed): label the bundle as a normal program/library
selinux_rotular() {
  command -v selinuxenabled >/dev/null 2>&1 && selinuxenabled || return 0
  local real
  real=$(readlink -f "$PREFIXO")
  if command -v semanage >/dev/null 2>&1; then
    semanage fcontext -a -t bin_t "$real/libexec(/.*)?" 2>/dev/null || semanage fcontext -m -t bin_t "$real/libexec(/.*)?"
    semanage fcontext -a -t lib_t "$real/lib(/.*)?" 2>/dev/null || semanage fcontext -m -t lib_t "$real/lib(/.*)?"
    restorecon -RF "$real"
    estado_set SELINUX "$real"
  else
    chcon -R -t bin_t "$real/libexec" && chcon -R -t lib_t "$real/lib"
  fi
  ok "SELinux: rótulos aplicados" "SELinux: labels applied"
}
selinux_desfazer() {
  local real
  real=$(estado_get SELINUX)
  [ -n "$real" ] && command -v semanage >/dev/null 2>&1 || return 0
  semanage fcontext -d "$real/libexec(/.*)?" 2>/dev/null
  semanage fcontext -d "$real/lib(/.*)?" 2>/dev/null
  return 0
}

# Talks to the service like the login screen does: open the reader once (firmware check)
testar_servico() {
  local dev saida i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    dev=$(busctl --system call net.reactivated.Fprint /net/reactivated/Fprint/Manager \
      net.reactivated.Fprint.Manager GetDefaultDevice 2>&1) && break
    sleep 1
  done
  case "$dev" in
    o\ *) dev=$(printf '%s' "$dev" | cut -d'"' -f2) ;;
    *) echo "NODEV $dev"; return 1 ;;
  esac
  saida=$(busctl --system --timeout=30 call net.reactivated.Fprint "$dev" net.reactivated.Fprint.Device Claim s "" 2>&1)
  local r=$?
  # the claim ends with the busctl connection
  if [ $r -ne 0 ]; then
    case "$saida" in
      *laimed*) echo "BUSY $saida"; return 0 ;;
      *) echo "OPEN $saida"; return 1 ;;
    esac
  fi
  echo "OK"
}

# --- PAM: only the distribution's own fingerprint login switch ------------------------------------

pam_backup() {
  local dirs=(etc/pam.d)
  [ -d /var/lib/pam ] && dirs+=(var/lib/pam)
  mkdir -p "$ESTADO/backup"
  [ -e "$ESTADO/backup/pam.tar" ] || tar -cf "$ESTADO/backup/pam.tar" -C / "${dirs[@]}" 2>/dev/null
}

# Debian/Ubuntu/Mint: libpam-fprintd ships the "fprintd" pam-auth-update profile (off by default)
pam_debian() {
  command -v pam-auth-update >/dev/null || return 1
  grep -q pam_fprintd /etc/pam.d/common-auth 2>/dev/null && return 0 # already on (distro, Fingwit...)
  [ -e /usr/share/pam-configs/fprintd ] || return 1
  DEBIAN_FRONTEND=noninteractive pam-auth-update --enable fprintd || return 1
  estado_set PAM_ATIVOU 1
  grep -q pam_fprintd /etc/pam.d/common-auth && grep -q pam_unix /etc/pam.d/common-auth
}
pam_debian_desfazer() {
  [ "$(estado_get PAM_ATIVOU)" = 1 ] && DEBIAN_FRONTEND=noninteractive pam-auth-update --disable fprintd
  return 0
}

# Fedora (also Atomic): authselect feature
pam_fedora() {
  command -v authselect >/dev/null && authselect current >/dev/null 2>&1 || return 1
  if authselect current | grep -q with-fingerprint; then return 0; fi
  authselect enable-feature with-fingerprint >/dev/null || return 1
  estado_set PAM_ATIVOU 1
  grep -q pam_fprintd /etc/pam.d/system-auth 2>/dev/null || grep -q pam_fprintd /etc/pam.d/fingerprint-auth
}
pam_fedora_desfazer() { [ "$(estado_get PAM_ATIVOU)" = 1 ] && authselect disable-feature with-fingerprint >/dev/null; return 0; }

# openSUSE: pam-config module
pam_suse() {
  command -v pam-config >/dev/null || return 1
  pam-config -q --fprintd 2>/dev/null | grep -q fprintd && return 0
  pam-config -a --fprintd || return 1
  estado_set PAM_ATIVOU 1
}
pam_suse_desfazer() { [ "$(estado_get PAM_ATIVOU)" = 1 ] && pam-config -d --fprintd; return 0; }

configurar_pam() {
  local metodo
  case "$FAMILIA" in
    debian | fedora | suse) metodo=$FAMILIA ;;
    *)
      info "Esta distribuição não tem um ajuste padrão de login com digital: a tela de login e o bloqueio de tela" \
        "This distribution has no standard fingerprint login switch: the GNOME/KDE login and lock screens"
      info "do GNOME/KDE já usam a digital sozinhos; para o sudo, veja o README." \
        "use the fingerprint on their own; for sudo, see the README."
      return 0 ;;
  esac
  modulo_pam_fprintd >/dev/null || { aviso "Módulo pam_fprintd não encontrado: digital no login não foi ativada." \
    "pam_fprintd module not found: fingerprint login was not enabled."; return 0; }
  pam_backup
  estado_set PAM_METODO "$metodo"
  if "pam_$metodo"; then
    ok "Digital ativada no login, desbloqueio de tela, sudo e janelas de senha (pelo ajuste padrão da distribuição; a senha continua valendo)" \
      "Fingerprint enabled for login, screen unlock, sudo and password dialogs (distribution standard switch; the password keeps working)"
  else
    aviso "Não consegui ligar a digital no login pelo ajuste padrão da distribuição; nada foi mudado nessa parte." \
      "Could not enable fingerprint login through the distribution switch; nothing was changed there."
    "pam_${metodo}_desfazer" >/dev/null 2>&1
    estado_set PAM_METODO ""
  fi
}
desfazer_pam() {
  local metodo
  metodo=$(estado_get PAM_METODO)
  [ -n "$metodo" ] && [ "$(estado_get PAM_ATIVOU)" = 1 ] || return 0
  "pam_${metodo}_desfazer" && ok "Login com digital desligado (como era antes)" "Fingerprint login switched off (as it was before)"
}

# Version 0.1.0 had its own PAM profile / marked lines and changed the power button
desfazer_legado() {
  local nome
  if [ -e "$LEGADO_PERFIL" ]; then
    # back to the PAM state saved before 0.1.0 touched it
    if [ -e "$ESTADO/backup/pam.tar" ]; then
      tar -xf "$ESTADO/backup/pam.tar" -C / etc/pam.d/common-auth etc/pam.d/common-account etc/pam.d/common-password \
        etc/pam.d/common-session etc/pam.d/common-session-noninteractive var/lib/pam 2>/dev/null
    fi
    rm -f "$LEGADO_PERFIL"
    ok "Perfil de login próprio da versão anterior removido (configuração original restaurada)" \
      "Own login profile of the previous version removed (original configuration restored)"
  fi
  for nome in $LEGADO_PAM_ARQUIVOS; do
    [ -e "/etc/pam.d/$nome" ] && grep -q "$LEGADO_MARCA\$" "/etc/pam.d/$nome" && sed -i "/$LEGADO_MARCA\$/d" "/etc/pam.d/$nome"
  done
  for nome in $(estado_get PAM_CRIADOS); do rm -f "/etc/pam.d/$nome"; done
  if [ -e "$LEGADO_LOGIND" ]; then
    rm -f "$LEGADO_LOGIND"
    ok "Ajuste do botão de ligar da versão anterior removido" "Power button setting of the previous version removed"
  fi
  case "$(estado_get PAM_METODO)" in debian | manual) [ "$(estado_get PAM_ATIVOU)" = 1 ] || estado_set PAM_METODO "" ;; esac
  [ -e "$ESTADO/estado" ] && sed -i '/^PAM_DESATIVADOS=/d; /^PAM_REGISTRADO=/d; /^PAM_CRIADOS=/d' "$ESTADO/estado"
  return 0
}

# --- main root actions ------------------------------------------------------------------------

voltar_atras() { # undo a failed install
  rm -f "$DROPIN"
  local f
  for f in $DROPINS_ANTIGOS; do [ -e "$ESTADO/backup/legado/$f" ] && mv "$ESTADO/backup/legado/$f" "$DROPIN_DIR/$f"; done
  if [ -d "$PREFIXO.antigo" ]; then rm -rf "$PREFIXO"; mv "$PREFIXO.antigo" "$PREFIXO"
  elif [ ! -e "$ESTADO/estado" ] || [ -z "$(estado_get VERSAO)" ]; then rm -rf "$PREFIXO"; fi
  systemctl daemon-reload
  systemctl restart fprintd 2>/dev/null || true
}

testar_servico_arquivo() { systemctl restart fprintd; testar_servico >"$ESTADO/.teste-servico"; }

instalar_atalho() {
  mkdir -p "$(dirname "$ATALHO_BIN")" "$(dirname "$ATALHO_DESKTOP")"
  printf '#!/bin/sh\n# fprint-538d menu: enroll, test, recognition level, update, uninstall\nexec bash %s/share/fprint-538d/instalar.sh --menu "$@"\n' "$PREFIXO" >"$ATALHO_BIN"
  chmod 755 "$ATALHO_BIN"
  cat >"$ATALHO_DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=Fingerprint reader
Name[pt]=Leitor de digital
Name[pt_BR]=Leitor de digital
Comment=Enroll and test fingerprints, recognition level, update or uninstall (Goodix 538d)
Comment[pt]=Cadastrar e testar digitais, nível de reconhecimento, atualizar ou desinstalar (Goodix 538d)
Comment[pt_BR]=Cadastrar e testar digitais, nível de reconhecimento, atualizar ou desinstalar (Goodix 538d)
Exec=$ATALHO_BIN
Icon=auth-fingerprint
Terminal=true
Categories=Settings;HardwareSettings;System;
Keywords=fingerprint;digital;fprint;biometric;biometria;
EOF
  chmod 644 "$ATALHO_DESKTOP"
}

raiz_instalar() { # pacote usuario pam(s/n) [limiar, empty = keep] [restaurar libfprint s/n]
  local pacote=$1 usuario=$2 pam=$3 nivel=${4:-} restaurar=${5:-n} f r
  mkdir -p "$ESTADO/backup"
  chmod 700 "$ESTADO"
  LOG=$ESTADO/instalar.log
  log "install $(cat "$pacote/share/fprint-538d/VERSAO" 2>/dev/null) on $NOME_DISTRO ($FAMILIA $IMUTAVEL) model $(modelo)"

  ok "Senha aceita" "Password accepted"
  instalar_pacotes_distro || { mostrar_log; fim_erro "Não consegui instalar o fprintd da distribuição. Instale os pacotes 'fprintd' e o módulo PAM dele e rode de novo." \
    "Could not install the distribution fprintd. Install 'fprintd' and its PAM module, then run again."; }
  [ "$restaurar" = s ] && restaurar_libfprint

  systemctl stop fprintd 2>/dev/null
  mkdir -p "$(readlink -f "$(dirname "$PREFIXO")")"
  rm -rf "$PREFIXO.novo" "$PREFIXO.antigo"
  cp -a "$pacote" "$PREFIXO.novo" || fim_erro "Falha ao copiar arquivos." "Failed to copy files."
  [ "$SELF" -ef "$PREFIXO.novo/share/fprint-538d/instalar.sh" ] || cp "$SELF" "$PREFIXO.novo/share/fprint-538d/instalar.sh"
  chown -R root:root "$PREFIXO.novo"
  chmod -R go-w "$PREFIXO.novo"
  [ -e "$PREFIXO" ] && mv "$PREFIXO" "$PREFIXO.antigo"
  mv "$PREFIXO.novo" "$PREFIXO"
  selinux_rotular
  instalar_atalho
  ok "Driver copiado para $PREFIXO" "Driver copied to $PREFIXO"

  mkdir -p "$DROPIN_DIR" "$ESTADO/backup/legado"
  for f in $DROPINS_ANTIGOS; do [ -e "$DROPIN_DIR/$f" ] && mv "$DROPIN_DIR/$f" "$ESTADO/backup/legado/$f"; done
  cat >"$DROPIN" <<EOF
# fprint-538d: Goodix 27c6:538d driver (https://github.com/$REPO_GH)
# Uninstall: bash $PREFIXO/share/fprint-538d/instalar.sh --desinstalar
[Service]
ExecStart=
ExecStart=$PREFIXO/libexec/fprintd
# Recognition level (bash instalar.sh --ajustar)
EnvironmentFile=-$AJUSTE_CONF
# Diagnostics (scores in the journal): uncomment, then systemctl restart fprintd
#Environment=G_MESSAGES_DEBUG=libfprint-print
EOF
  if [ -n "$nivel" ]; then gravar_nivel "$nivel"; fi
  systemctl daemon-reload
  esperar "Ligando o leitor com o novo driver e conferindo o firmware (até 30 s)" "Starting the reader with the new driver and checking the firmware (up to 30 s)" \
    testar_servico_arquivo
  r=$(cat "$ESTADO/.teste-servico" 2>/dev/null)
  rm -f "$ESTADO/.teste-servico"
  case "$r" in
    OK) ok "Leitor aberto pelo novo driver (firmware compatível, calibração automática)" "Reader opened by the new driver (compatible firmware, automatic calibration)" ;;
    BUSY*) aviso "Leitor em uso por outro programa; a verificação será no cadastro." "Reader busy in another program; it will be checked during enrollment." ;;
    *)
      log "check failed: $r"
      voltar_atras
      if printf '%s' "$r" | grep -qi firmware; then
        fim_erro "O firmware deste leitor é diferente do suportado (GF5298_GM168SEC_APP_13016). Instalação desfeita; nada foi gravado no leitor." \
          "This reader's firmware differs from the supported one (GF5298_GM168SEC_APP_13016). Installation undone; nothing was written to the reader."
      fi
      fim_erro "O serviço não conseguiu abrir o leitor ($r). Instalação desfeita." \
        "The service could not open the reader ($r). Installation undone."
      ;;
  esac
  rm -rf "$PREFIXO.antigo"

  desfazer_legado
  if [ "$pam" = s ]; then
    configurar_pam
  fi

  estado_set VERSAO "$(cat "$PREFIXO/share/fprint-538d/VERSAO" 2>/dev/null)"
  estado_set USUARIO "$usuario"
  estado_set FAMILIA "$FAMILIA"
}

raiz_desinstalar() { # apagar_digitais(s/n)
  local f
  LOG=$ESTADO/instalar.log
  titulo "Removendo o fprint-538d" "Removing fprint-538d"
  desfazer_pam
  desfazer_legado
  rm -f "$DROPIN" "$AJUSTE_CONF" "$ATALHO_BIN" "$ATALHO_DESKTOP"
  for f in $DROPINS_ANTIGOS; do rm -f "$DROPIN_DIR/$f"; done
  rmdir "$DROPIN_DIR" 2>/dev/null
  selinux_desfazer
  rm -rf "$(readlink -f "$PREFIXO")" "$PREFIXO" "$PREFIXO.antigo" "$PREFIXO.novo"
  systemctl daemon-reload
  systemctl restart fprintd 2>/dev/null || true
  if [ "$1" = s ]; then
    rm -rf /var/lib/fprint/*/goodixtls53xd
    ok "Digitais cadastradas apagadas" "Enrolled fingerprints deleted"
  fi
  rm -rf "$ESTADO"
  ok "Removido. O sistema voltou ao fprintd original da distribuição." "Removed. The system is back to the distribution fprintd."
}

gravar_nivel() { # limiar (no restart)
  case "$1" in *[!0-9]* | '') return 1 ;; esac
  # installs from version 0.1.0 do not read the file yet
  grep -q '^EnvironmentFile=' "$DROPIN" || printf 'EnvironmentFile=-%s\n' "$AJUSTE_CONF" >>"$DROPIN"
  if [ "$1" = "$NIVEL_PADRAO" ]; then
    rm -f "$AJUSTE_CONF"
  else
    cat >"$AJUSTE_CONF" <<EOF
# fprint-538d recognition level (bash $PREFIXO/share/fprint-538d/instalar.sh --ajustar)
# Minimum score (0-100) to accept a finger. Default $NIVEL_PADRAO; lower accepts more, also wrong fingers.
FPRINT_BZ3_THRESHOLD=$1
EOF
    chmod 644 "$AJUSTE_CONF"
  fi
}

raiz_ajustar() { # limiar
  [ -e "$DROPIN" ] || fim_erro "O fprint-538d não está instalado." "fprint-538d is not installed."
  gravar_nivel "$1" || exit 1
  systemctl daemon-reload
  systemctl restart fprintd 2>/dev/null || true
}

# ---------------------------------------------------------------------------------------------
# USER PART

como_root() { # runs this script's root part
  local bash_bin
  bash_bin=$(command -v bash)
  if [ "$(id -u)" != 0 ]; then
    if [ "$TEM_TTY" = 1 ] && command -v sudo >/dev/null; then
      if ! sudo -n true 2>/dev/null; then
        printf '\n   %s🔑 %s%s\n' "$C_N" "$(t "Agora digite a SUA senha (a mesma de entrar no computador) e aperte Enter." \
          "Now type YOUR password (the one you use to log in) and press Enter.")" "$C_0"
        info "Enquanto você digita, nada aparece na tela — é normal." "Nothing shows on screen while you type — that is normal."
      fi
    else
      info "Uma janela vai pedir a sua senha." "A window will ask for your password."
    fi
  fi
  if [ "$(id -u)" = 0 ]; then "$bash_bin" "$SELF" --lang "$L" --interno "$@"
  elif [ "$TEM_TTY" = 1 ] && command -v sudo >/dev/null; then sudo "$bash_bin" "$SELF" --lang "$L" --interno "$@"
  elif command -v pkexec >/dev/null; then pkexec "$bash_bin" "$SELF" --lang "$L" --interno "$@"
  else sudo "$bash_bin" "$SELF" --lang "$L" --interno "$@"; fi
}

baixar_pacote() { baixar "$URL_PACOTE" "$1" && baixar "$URL_PACOTE.sha256" "$1.sha256"; }
baixar() { # url destino
  if command -v curl >/dev/null; then curl -fsSL --retry 2 -o "$2" "$1"
  elif command -v wget >/dev/null; then wget -q -O "$2" "$1"
  else return 2; fi
}

obter_pacote() { # sets PACOTE_DIR
  local arq=""
  if [ -n "$OPT_PACOTE" ]; then
    arq=$OPT_PACOTE
    [ -r "$arq" ] || fim_erro "Arquivo não encontrado: $arq" "File not found: $arq"
  elif [ "$OPT_COMPILAR" = 1 ]; then
    local fonte
    fonte=$(dirname "$SELF")
    if [ ! -x "$fonte/construir/no-conteiner.sh" ]; then
      command -v git >/dev/null || fim_erro "Preciso do 'git' para compilar." "'git' is needed to build."
      fonte=$TMPD/fonte
      esperar "Baixando o código" "Downloading the source" git clone -q --depth 1 "https://github.com/$REPO_GH.git" "$fonte" || fim_erro "Falha ao baixar o código." "Failed to download the source."
    fi
    command -v podman >/dev/null || command -v docker >/dev/null ||
      fim_erro "Para compilar preciso do podman ou docker (o sistema não é alterado). Instale um deles e rode de novo." \
        "Building needs podman or docker (keeps the system clean). Install one and run again."
    esperar "Compilando o driver (10 a 20 minutos na primeira vez)" "Building the driver (10 to 20 minutes the first time)" \
      "$fonte/construir/no-conteiner.sh" || { mostrar_log; fim_erro "A compilação falhou." "The build failed."; }
    ok "Driver compilado" "Driver built"
    arq=$fonte/dist/fprint-538d-x86_64.tar.gz
  else
    arq=$TMPD/fprint-538d-x86_64.tar.gz
    if ! esperar "Baixando o driver (5 MB)" "Downloading the driver (5 MB)" baixar_pacote "$arq"; then
      fim_erro "Não consegui baixar o pacote. Confira a internet. Alternativa: bash instalar.sh --compilar" \
        "Could not download the bundle. Check the internet connection. Alternative: bash instalar.sh --compilar"
    fi
    (cd "$TMPD" && sha256sum -c --quiet fprint-538d-x86_64.tar.gz.sha256) ||
      fim_erro "O arquivo baixado está corrompido (soma de verificação não bate). Tente de novo." \
        "The downloaded file is corrupted (checksum mismatch). Try again."
    ok "Pacote baixado e conferido" "Bundle downloaded and verified"
  fi
  tar -xzf "$arq" -C "$TMPD" || fim_erro "Pacote inválido: $arq" "Invalid bundle: $arq"
  PACOTE_DIR=$TMPD/fprint-538d
  [ -x "$PACOTE_DIR/libexec/fprintd" ] || fim_erro "Pacote incompleto: $arq" "Incomplete bundle: $arq"
  chmod -R a+rX "$TMPD"
  if [ ! -f "$0" ] && [ -f "$PACOTE_DIR/share/fprint-538d/instalar.sh" ]; then SELF=$PACOTE_DIR/share/fprint-538d/instalar.sh; fi
  ok "Versão do driver: $(cat "$PACOTE_DIR/share/fprint-538d/VERSAO" 2>/dev/null)" "Driver version: $(cat "$PACOTE_DIR/share/fprint-538d/VERSAO" 2>/dev/null)"
}

verificar() {
  [ "$(uname -m)" = x86_64 ] || fim_erro "Só computadores x86_64 (Intel/AMD) são suportados." "Only x86_64 (Intel/AMD) computers are supported."
  glibc_ok || fim_erro "Este sistema é antigo demais ou não usa a glibc (preciso da glibc $GLIBC_MIN ou mais nova)." \
    "This system is too old or does not use glibc (glibc $GLIBC_MIN or newer needed)."
  [ -d /run/systemd/system ] || fim_erro "Este sistema não usa systemd; não é suportado." "This system does not use systemd; not supported."
  sensor_presente || fim_erro "Leitor Goodix 27c6:538d não encontrado neste computador. Este instalador serve só para ele." \
    "Goodix 27c6:538d reader not found in this computer. This installer is only for that reader."
  ok "Leitor Goodix 27c6:538d encontrado" "Goodix 27c6:538d reader found"
  info "Computador: $(cat /sys/class/dmi/id/sys_vendor 2>/dev/null) $(modelo)" "Computer: $(cat /sys/class/dmi/id/sys_vendor 2>/dev/null) $(modelo)"
  detectar_distro
  case "$FAMILIA" in
    desconhecida)
      aviso "Distribuição não reconhecida ($NOME_DISTRO). Vou tentar, mas o fprintd e o pam_fprintd precisam já estar instalados." \
        "Unrecognised distribution ($NOME_DISTRO). I will try, but fprintd and pam_fprintd must already be installed."
      pacotes_distro_ok || fim_erro "Instale os pacotes do fprintd (serviço, ferramentas fprintd-* e módulo PAM) pelo gerenciador da sua distribuição e rode de novo." \
        "Install the fprintd packages (service, fprintd-* tools and PAM module) with your package manager and run again." ;;
    *) ok "Sistema: $NOME_DISTRO (família $FAMILIA$([ "$IMUTAVEL" = 0 ] || echo ", imutável"))" "System: $NOME_DISTRO ($FAMILIA family$([ "$IMUTAVEL" = 0 ] || echo ", immutable"))" ;;
  esac
  local livre
  livre=$(df -Pm "$(readlink -f /opt 2>/dev/null || echo /)" 2>/dev/null | awk 'NR==2{print $4}')
  [ "${livre:-100}" -ge 50 ] || fim_erro "Pouco espaço livre em disco (preciso de 50 MB)." "Not enough disk space (50 MB needed)."
  LIBFPRINT_TROCADA=0
  if [ "$IMUTAVEL" = 0 ] && libfprint_alterada >/dev/null; then
    LIBFPRINT_TROCADA=1
    aviso "A biblioteca de digital do sistema foi trocada por outro instalador (por exemplo, um script que compila outro driver)." \
      "The system fingerprint library was replaced by another installer (for example, a script that builds another driver)."
  fi
}

# --- enrollment, test and menu ------------------------------------------------------------------

DEDOS=(right-index-finger right-middle-finger right-ring-finger right-little-finger right-thumb
       left-index-finger left-middle-finger left-ring-finger left-little-finger left-thumb)
nome_dedo() {
  case "$1" in
    right-index-finger) t "indicador direito" "right index finger" ;;
    right-middle-finger) t "médio direito" "right middle finger" ;;
    right-ring-finger) t "anelar direito" "right ring finger" ;;
    right-little-finger) t "mínimo direito" "right little finger" ;;
    right-thumb) t "polegar direito" "right thumb" ;;
    left-index-finger) t "indicador esquerdo" "left index finger" ;;
    left-middle-finger) t "médio esquerdo" "left middle finger" ;;
    left-ring-finger) t "anelar esquerdo" "left ring finger" ;;
    left-little-finger) t "mínimo esquerdo" "left little finger" ;;
    left-thumb) t "polegar esquerdo" "left thumb" ;;
    *) printf '%s' "$1" ;;
  esac
}
dedos_cadastrados() { fprintd-list "$USER" 2>/dev/null | sed -n 's/^ *- *#[0-9]*: *//p'; }
nomes_cadastrados() {
  local d lista=""
  for d in $(dedos_cadastrados); do lista="$lista, $(nome_dedo "$d")"; done
  printf '%s' "${lista#, }"
}

# One enrollment, translating fprintd-enroll into plain guidance; 0 when completed
cadastro_guiado() { # dedo
  local dedo=$1 n=0 linha res=1
  fprintd-delete "$USER" -f "$dedo" >/dev/null 2>&1
  printf '\n   %s👉 %s%s\n' "$C_N" "$(t "Encoste o $(nome_dedo "$dedo") no leitor agora, de leve (toque 1 de $TOQUES)" \
    "Touch the reader with your $(nome_dedo "$dedo") now, lightly (touch 1 of $TOQUES)")" "$C_0"
  while IFS= read -r linha; do
    log "enroll: $linha"
    case "$linha" in
      *enroll-stage-passed*)
        n=$((n + 1))
        ok "[$n/$TOQUES] $(t "Lido! Levante o dedo e encoste de novo, numa posição um pouco diferente" "Got it! Lift the finger and touch again, in a slightly different position")" \
          "[$n/$TOQUES] $(t "Lido! Levante o dedo e encoste de novo, numa posição um pouco diferente" "Got it! Lift the finger and touch again, in a slightly different position")" ;;
      *enroll-retry-scan* | *enroll-swipe-too-short* | *enroll-finger-not-centered* | *enroll-remove-and-retry*)
        aviso "Não deu para ler esse toque. Levante o dedo e encoste de novo, de leve" "Could not read that touch. Lift the finger and touch again, lightly" ;;
      *enroll-completed*) res=0 ;;
      *enroll-duplicate*) aviso "Esse dedo já está cadastrado." "That finger is already enrolled." ;;
      *laimed*) aviso "O leitor está sendo usado por outro programa (Configurações, app de digital). Feche-o e tente de novo." \
        "The reader is in use by another program (Settings, a fingerprint app). Close it and try again." ;;
      *enroll-failed* | *enroll-data-full* | *enroll-disconnected* | *enroll-unknown-error*)
        aviso "O cadastro falhou ($linha)." "Enrollment failed ($linha)." ;;
    esac
  done < <(timeout -k 5 600 stdbuf -oL fprintd-enroll -f "$dedo" 2>&1)
  if [ $res = 0 ]; then
    ok "Cadastro do $(nome_dedo "$dedo") concluído!" "$(nome_dedo "$dedo") enrolled!"
  else
    aviso "O cadastro não terminou. Você pode tentar de novo pelo menu \"Leitor de digital\"." \
      "Enrollment did not finish. You can try again from the \"Fingerprint reader\" menu."
  fi
  return $res
}

# Asks which finger, explains and enrolls
cadastrar_dedo() {
  local dedo esc i ja marca
  ja=" $(dedos_cadastrados | tr "\n" " ") "
  dedo=${DEDOS[0]}
  if [ "$SIM" = 0 ] && [ "$TEM_TTY" = 1 ]; then
    info "Qual dedo cadastrar?" "Which finger to enroll?"
    for i in "${!DEDOS[@]}"; do
      marca=""
      case "$ja" in *" ${DEDOS[$i]} "*) marca=$(t "  (já cadastrado: será refeito)" "  (already enrolled: will be redone)") ;; esac
      printf '      %2d) %s%s\n' $((i + 1)) "$(nome_dedo "${DEDOS[$i]}")" "$marca"
    done
    printf '   %s%s%s ' "$C_N" "$(t "Digite o número e aperte Enter (só Enter = 1):" "Type the number and press Enter (just Enter = 1):")" "$C_0"
    read -r esc <&3 || esc=1
    case "$esc" in [1-9] | 10) dedo=${DEDOS[$((esc - 1))]} ;; esac
  fi
  cat <<EOF

   $(t "COMO FAZER O CADASTRO ($TOQUES toques, uns 2 minutos):" "HOW TO ENROLL ($TOQUES touches, about 2 minutes):")
     • $(t "o leitor é o quadradinho de digital — em muitos Dell, é o botão de ligar" "the reader is the small fingerprint square — on many Dell laptops, the power button")
     • $(t "ENCOSTE DE LEVE, sem apertar (apertar o botão de ligar pode desligar o computador)" "TOUCH LIGHTLY, do not press (pressing the power button may turn the computer off)")
     • $(t "a cada toque, levante o dedo por completo e encoste numa posição um pouco diferente:" "after each touch, lift the finger completely and touch in a slightly different position:")
       $(t "centro, ponta, laterais, e o dedo um pouco girado para os dois lados" "center, tip, sides, and the finger slightly rotated both ways")
     • $(t "a tela mostra cada toque lido; se pedir para repetir, é normal" "the screen shows each touch read; being asked to repeat is normal")

EOF
  esperar_enter "Aperte Enter quando estiver pronto..." "Press Enter when ready..."
  cadastro_guiado "$dedo"
}

cadastrar() { # install flow
  local ja
  ja=$(nomes_cadastrados)
  if [ -n "$ja" ]; then
    info "Digitais já cadastradas: $ja" "Fingerprints already enrolled: $ja"
    perguntar "Manter essas digitais e pular o cadastro?" "Keep them and skip enrollment?" s && return 0
  fi
  [ "$TEM_TTY" = 1 ] || { info "Cadastre depois pelo menu \"Leitor de digital\"." "Enroll later from the \"Fingerprint reader\" menu."; return 0; }
  cadastrar_dedo && perguntar "Testar agora (um toque)?" "Test now (one touch)?" s && testar_dedo
  return 0
}

testar_dedo() {
  local linha res=tempo
  printf '\n   %s👉 %s%s\n' "$C_N" "$(t "Encoste um dedo CADASTRADO no leitor agora, de leve (você tem 20 segundos)" \
    "Touch the reader with an ENROLLED finger now, lightly (you have 20 seconds)")" "$C_0"
  while IFS= read -r linha; do
    log "verify: $linha"
    case "$linha" in
      *verify-match*) res=sim ;;
      *verify-no-match*) res=nao ;;
      *verify-retry-scan* | *verify-swipe-too-short* | *verify-finger-not-centered* | *verify-remove-and-retry*)
        aviso "Não deu para ler. Levante e encoste de novo, de leve" "Could not read it. Lift and touch again, lightly" ;;
      *"No fingers enrolled"* | *no-enrolled*) res=nenhum ;;
      *laimed*) res=ocupado ;;
    esac
  done < <(timeout -k 3 20 stdbuf -oL fprintd-verify -f any 2>&1)
  case $res in
    sim) ok "Reconhecido!" "Recognised!" ;;
    nao) aviso "Não reconhecido. Tente de novo encostando de leve. Se errar muito: cadastre de novo ou use o nível Tolerante." \
      "Not recognised. Try again touching lightly. If it fails a lot: enroll again or use the Tolerant level." ;;
    nenhum) aviso "Nenhuma digital cadastrada ainda." "No fingerprint enrolled yet." ;;
    ocupado) aviso "O leitor está sendo usado por outro programa. Feche-o e tente de novo." "The reader is in use by another program. Close it and try again." ;;
    *) aviso "Nenhum toque em 20 segundos." "No touch in 20 seconds." ;;
  esac
}

apagar_digitais() {
  local ja
  ja=$(nomes_cadastrados)
  [ -n "$ja" ] || { info "Nenhuma digital cadastrada." "No fingerprint enrolled."; return 0; }
  info "Digitais cadastradas: $ja" "Enrolled fingerprints: $ja"
  perguntar "Apagar TODAS as suas digitais?" "Delete ALL your fingerprints?" n || return 0
  fprintd-delete "$USER" >/dev/null 2>&1 && ok "Digitais apagadas." "Fingerprints deleted."
}

nome_nivel() {
  case "$1" in
    "${NIVEIS[0]}") t "Rigoroso" "Strict" ;;
    "${NIVEIS[1]}") t "Padrão" "Default" ;;
    "${NIVEIS[2]}") t "Tolerante" "Tolerant" ;;
    *) printf '%s' "$1" ;;
  esac
}

principal_menu() {
  [ -e "$DROPIN" ] || fim_erro "O leitor de digital (fprint-538d) não está instalado." "The fingerprint reader (fprint-538d) is not installed."
  local esc ja
  while true; do
    ja=$(nomes_cadastrados)
    printf '\n%s━━ %s ━━%s\n' "$C_AZ" "$(t "Leitor de digital — o que você quer fazer?" "Fingerprint reader — what do you want to do?")" "$C_0"
    info "Digitais cadastradas: ${ja:-nenhuma}" "Enrolled fingerprints: ${ja:-none}"
    info "Nível de reconhecimento: $(nome_nivel "$(nivel_atual)")" "Recognition level: $(nome_nivel "$(nivel_atual)")"
    printf '\n'
    printf '      1) %s\n' "$(t "Cadastrar um dedo" "Enroll a finger")"
    printf '      2) %s\n' "$(t "Testar a digital" "Test the fingerprint")"
    printf '      3) %s\n' "$(t "Nível de reconhecimento (para dedos difíceis)" "Recognition level (for hard fingers)")"
    printf '      4) %s\n' "$(t "Apagar digitais" "Delete fingerprints")"
    printf '      5) %s\n' "$(t "Atualizar ou reparar o driver" "Update or repair the driver")"
    printf '      6) %s\n' "$(t "Desinstalar" "Uninstall")"
    printf '      0) %s\n' "$(t "Sair" "Exit")"
    printf '   %s%s%s ' "$C_N" "$(t "Digite o número e aperte Enter:" "Type the number and press Enter:")" "$C_0"
    read -r esc <&3 || exit 0
    case "$esc" in
      1) cadastrar_dedo && perguntar "Testar agora (um toque)?" "Test now (one touch)?" s && testar_dedo ;;
      2) testar_dedo ;;
      3) principal_ajustar ;;
      4) apagar_digitais ;;
      5) exec bash "$SELF" --lang "$L" ;;
      6) principal_desinstalar; exit 0 ;;
      0) exit 0 ;;
      *) continue ;;
    esac
    esperar_enter "Aperte Enter para voltar ao menu..." "Press Enter to go back to the menu..."
  done
}

principal_instalar() {
  printf '\n%s fprint-538d — %s%s\n' "$C_N" "$(t "instalador do leitor de digital Goodix 538d" "Goodix 538d fingerprint reader installer")" "$C_0"
  cat <<EOF

   $(t "O que vai acontecer (uns 5 minutos):" "What will happen (about 5 minutes):")
     1. $(t "conferir se este computador tem o leitor" "check that this computer has the reader")
     2. $(t "duas perguntas rápidas" "two quick questions")
     3. $(t "baixar o driver" "download the driver")
     4. $(t "instalar (pede a sua senha uma vez)" "install it (asks for your password once)")
     5. $(t "cadastrar o seu dedo ($TOQUES toques leves no leitor)" "enroll your finger ($TOQUES light touches on the reader)")
   $(t "Nada é gravado no leitor. Para cancelar: Ctrl+C." "Nothing is written to the reader. To cancel: Ctrl+C.")
EOF
  [ -e "$PREFIXO/share/fprint-538d/VERSAO" ] &&
    info "Já está instalado: será atualizado/reparado, mantendo as suas digitais." "Already installed: it will be updated/repaired, keeping your fingerprints."
  printf '\n'
  esperar_enter "Aperte Enter para começar..." "Press Enter to start..."

  passo 1 "Conferindo este computador" "Checking this computer"
  verificar

  passo 2 "Perguntas" "Questions"
  local pam=s
  perguntar "Usar a digital para entrar no sistema, desbloquear a tela, sudo e janelas de senha? (a senha continua valendo)" \
    "Use the fingerprint to log in, unlock the screen, sudo and password dialogs? (the password keeps working)" s || pam=n
  local restaurar=n
  if [ "$LIBFPRINT_TROCADA" = 1 ]; then
    perguntar "Restaurar a biblioteca original do sistema? (recomendado; este driver não depende dela)" \
      "Restore the system's original library? (recommended; this driver does not depend on it)" s && restaurar=s
  fi
  NIVEL_ESCOLHIDO=$OPT_NIVEL
  if [ -z "$OPT_NIVEL" ] && [ "$SIM" = 0 ] && [ "$TEM_TTY" = 1 ]; then
    printf '\n'
    escolher_nivel "$(nivel_atual)"
  fi

  passo 3 "Baixando o driver" "Downloading the driver"
  obter_pacote

  passo 4 "Instalando" "Installing"
  como_root instalar "$PACOTE_DIR" "$USER" "$pam" "$NIVEL_ESCOLHIDO" "$restaurar"
  local r=$?
  [ $r -eq 3 ] && exit 0
  [ $r -eq 0 ] || exit $r
  rm -rf "${XDG_CONFIG_HOME:-$HOME/.config}/fprint-538d" # left by version 0.1.0

  passo 5 "Cadastrando o seu dedo" "Enrolling your finger"
  if [ "$OPT_SEM_CADASTRO" = 1 ]; then info "Pulado (--sem-cadastro)." "Skipped (--no-enroll)."; else cadastrar; fi

  cat <<EOF

${C_VD}━━ $(t "Pronto! O leitor de digital está instalado." "Done! The fingerprint reader is installed.") ━━${C_0}

   $(t "Para cadastrar outros dedos, testar, mudar o nível de reconhecimento," "To enroll more fingers, test, change the recognition level,")
   $(t "atualizar ou desinstalar, abra o menu de aplicativos e procure:" "update or uninstall, open the applications menu and look for:")

        ${C_N}$(t "Leitor de digital" "Fingerprint reader")${C_0}      $(t "(ou digite  leitor-digital  num terminal)" "(or type  leitor-digital  in a terminal)")

   $(t "Conte como foi no seu modelo:" "Tell us how it went on your model:") https://github.com/$REPO_GH/issues

EOF
}

nivel_atual() {
  local v
  v=$(sed -n 's/^FPRINT_BZ3_THRESHOLD=//p' "$AJUSTE_CONF" 2>/dev/null)
  echo "${v:-$NIVEL_PADRAO}"
}

nivel_de_nome() { # name or number -> threshold
  case "${1,,}" in
    1 | rigoroso | strict) echo "${NIVEIS[0]}" ;;
    2 | padrao | padrão | default) echo "${NIVEIS[1]}" ;;
    3 | tolerante | tolerant) echo "${NIVEIS[2]}" ;;
    *) return 1 ;;
  esac
}

# Menu; sets NIVEL_ESCOLHIDO (empty = keep the current one)
escolher_nivel() {
  local atual=$1 esc i
  local nomes_pt=("Rigoroso — recusa mais, inclusive o seu dedo às vezes" "Padrão (recomendado)" "Tolerante — para dedos difíceis (calos, pele seca); aceita com nota menor")
  local nomes_en=("Strict — rejects more, sometimes your own finger too" "Default (recommended)" "Tolerant — for hard fingers (calluses, dry skin); accepts lower scores")
  NIVEL_ESCOLHIDO=""
  info "Nível de reconhecimento (dá para mudar depois com --ajustar):" "Recognition level (can be changed later with --tune):"
  for i in 0 1 2; do
    printf '      %d) %s  [%s]%s\n' $((i + 1)) "$(t "${nomes_pt[$i]}" "${nomes_en[$i]}")" "${NIVEIS[$i]}" \
      "$([ "${NIVEIS[$i]}" = "$atual" ] && t "  ← atual" "  ← current")"
  done
  info "Nos testes, dedos errados tiraram no máximo 51; o Tolerante (55) ainda fica acima disso." \
    "In the tests, wrong fingers scored at most 51; Tolerant (55) is still above that."
  printf '   %s%s%s ' "$C_N" "$(t "Digite o número e aperte Enter (só Enter = manter $(nome_nivel "$atual")):" "Type the number and press Enter (just Enter = keep $(nome_nivel "$atual")):")" "$C_0"
  read -r esc <&3 || esc=""
  case "$esc" in 1 | 2 | 3) NIVEL_ESCOLHIDO=${NIVEIS[$((esc - 1))]} ;; esac
  [ "$NIVEL_ESCOLHIDO" = "$atual" ] && NIVEL_ESCOLHIDO=""
  return 0
}

principal_ajustar() {
  [ -e "$DROPIN" ] || fim_erro "O fprint-538d não está instalado. Instale primeiro: bash instalar.sh" \
    "fprint-538d is not installed. Install first: bash instalar.sh"
  local atual
  atual=$(nivel_atual)
  titulo "Nível de reconhecimento" "Recognition level"
  if [ -n "$OPT_NIVEL" ]; then
    NIVEL_ESCOLHIDO=$OPT_NIVEL
  else
    [ "$TEM_TTY" = 1 ] || fim_erro "Rode num terminal, ou use --nivel tolerante|padrao|rigoroso." \
      "Run it in a terminal, or use --nivel tolerant|default|strict."
    escolher_nivel "$atual"
  fi
  if [ -z "$NIVEL_ESCOLHIDO" ] || [ "$NIVEL_ESCOLHIDO" = "$atual" ]; then
    info "Nada mudou (nível $atual)." "Nothing changed (level $atual)."
    return 0
  fi
  como_root ajustar "$NIVEL_ESCOLHIDO" || exit 1
  ok "Nível de reconhecimento: $NIVEL_ESCOLHIDO (vale a partir do próximo toque)" "Recognition level: $NIVEL_ESCOLHIDO (applies from the next touch)"
}

principal_desinstalar() {
  detectar_distro
  [ -e "$PREFIXO" ] || [ -e "$ESTADO" ] || [ -e "$DROPIN" ] || fim_erro "O fprint-538d não está instalado." "fprint-538d is not installed."
  perguntar "Remover o fprint-538d e voltar ao fprintd original da distribuição?" "Remove fprint-538d and go back to the distribution fprintd?" s || exit 0
  local apagar=n
  perguntar "Apagar também as digitais cadastradas (não servem no fprintd original)?" "Also delete the enrolled fingerprints (unusable with the original fprintd)?" s && apagar=s
  local copia
  copia=$(mktemp "${TMPDIR:-/tmp}/fprint-538d-instalar.XXXXXX.sh")
  cp "$SELF" "$copia" && chmod 755 "$copia" && SELF=$copia # the original is deleted by the root part
  como_root desinstalar "$apagar" || { rm -f "$copia"; exit 1; }
  rm -f "$copia"
  rm -rf "${XDG_CONFIG_HOME:-$HOME/.config}/fprint-538d"
}

# ---------------------------------------------------------------------------------------------

# Tests load the functions only (construir/testar-pam.sh)
[ "${FPRINT538D_SO_FUNCOES:-}" = 1 ] && return 0

SELF=$(readlink -f "$0" 2>/dev/null || echo "$0")
ACAO=instalar OPT_PACOTE="" OPT_COMPILAR=0 OPT_SEM_CADASTRO=0 OPT_NIVEL="" NIVEL_ESCOLHIDO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --desinstalar | --uninstall) ACAO=desinstalar ;;
    --ajustar | --tune) ACAO=ajustar ;;
    --menu) ACAO=menu ;;
    --nivel | --level)
      OPT_NIVEL=$(nivel_de_nome "${2:-}") || fim_erro "Nível desconhecido: ${2:-} (use rigoroso, padrao ou tolerante)" \
        "Unknown level: ${2:-} (use strict, default or tolerant)"
      shift ;;
    --pacote | --bundle) OPT_PACOTE=$(readlink -f "${2:-}"); shift ;;
    --compilar | --build) OPT_COMPILAR=1 ;;
    --sem-cadastro | --no-enroll) OPT_SEM_CADASTRO=1 ;;
    --sim | --yes) SIM=1 ;;
    --lang) L=${2:-en}; shift ;;
    --interno)
      shift
      [ "$(id -u)" = 0 ] || exit 1
      detectar_distro
      case "${1:-}" in
        instalar) shift; raiz_instalar "$@" ;;
        desinstalar) shift; raiz_desinstalar "$@" ;;
        ajustar) shift; raiz_ajustar "$@" ;;
        *) exit 1 ;;
      esac
      exit $? ;;
    -h | --help | --ajuda) sed -n '2,20p' "$SELF"; exit 0 ;;
    *) fim_erro "Opção desconhecida: $1" "Unknown option: $1" ;;
  esac
  shift
done

if [ "$(id -u)" = 0 ]; then
  fim_erro "Rode como usuário normal, sem sudo: bash instalar.sh (a senha será pedida quando precisar)." \
    "Run as your normal user, without sudo: bash instalar.sh (the password is asked when needed)."
fi
TMPD=$(mktemp -d "${TMPDIR:-/tmp}/fprint-538d.XXXXXX")
mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}" && LOG=${XDG_CACHE_HOME:-$HOME/.cache}/fprint-538d.log
trap 'rm -rf "$TMPD"' EXIT

# Everything below runs only after bash has read the whole script, so it also works as
# "... | bash": the keyboard becomes the standard input only then.
principal() {
  if [ "$TEM_TTY" = 1 ] && [ ! -t 0 ]; then exec 0<&3; fi
  case "$ACAO" in
    instalar) principal_instalar ;;
    desinstalar) principal_desinstalar ;;
    ajustar) principal_ajustar ;;
    menu) principal_menu ;;
  esac
}
principal; exit $?
