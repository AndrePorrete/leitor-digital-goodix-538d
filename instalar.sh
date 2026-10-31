#!/usr/bin/env bash
# fprint-538d — fingerprint reader Goodix 27c6:538d on Linux (Dell Inspiron 5590, 5402, 5409, 3501,
# 7506, Latitude 3410, Vostro 3500...). Installs a patched fprintd + libfprint in /opt/fprint-538d,
# next to the distribution packages (nothing of the distribution is overwritten).
#
#   Install / repair / update:  bash instalar.sh
#   Uninstall:                  bash instalar.sh --desinstalar      (or --uninstall)
#   Recognition level:          bash instalar.sh --ajustar          (or --tune)
#   Options:                    --pacote FILE.tar.gz   use a local bundle instead of downloading
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

if [ -t 1 ]; then C_AZ=$'\033[1;36m' C_VD=$'\033[1;32m' C_AM=$'\033[1;33m' C_VM=$'\033[1;31m' C_N=$'\033[1m' C_0=$'\033[0m'
else C_AZ='' C_VD='' C_AM='' C_VM='' C_N='' C_0=''; fi
LOG=""
log() { [ -z "$LOG" ] || printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$LOG" 2>/dev/null || true; }
titulo() { printf '\n%s== %s%s\n' "$C_AZ" "$(t "$1" "$2")" "$C_0"; log "== $2"; }
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
  if [ "$padrao" = s ]; then opcoes=$(t "[S/n]" "[Y/n]"); else opcoes=$(t "[s/N]" "[y/N]"); fi
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
  titulo "Instalando o fprintd da distribuição (programa base do leitor)" "Installing the distribution fprintd (reader base service)"
  case "$FAMILIA:$IMUTAVEL" in
    debian:0) apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq fprintd libpam-fprintd ;;
    fedora:0) dnf install -y -q fprintd fprintd-pam ;;
    fedora:ostree | *:ostree)
      rpm-ostree install --idempotent fprintd fprintd-pam || return 1
      aviso "Pacotes adicionados à imagem do sistema. REINICIE o computador e rode este instalador de novo." \
        "Packages added to the system image. REBOOT the computer and run this installer again."
      exit 3 ;;
    arch:0) pacman -S --needed --noconfirm fprintd ;;
    suse:0) zypper -n -q install fprintd fprintd-pam ;;
    suse:transactional)
      transactional-update -n pkg install fprintd fprintd-pam || return 1
      aviso "Pacotes instalados num novo instantâneo. REINICIE e rode este instalador de novo." \
        "Packages installed in a new snapshot. REBOOT and run this installer again."
      exit 3 ;;
    *) return 1 ;;
  esac
  pacotes_distro_ok
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

raiz_instalar() { # pacote usuario pam(s/n)
  local pacote=$1 usuario=$2 pam=$3 f r
  mkdir -p "$ESTADO/backup"
  chmod 700 "$ESTADO"
  LOG=$ESTADO/instalar.log
  log "install $(cat "$pacote/share/fprint-538d/VERSAO" 2>/dev/null) on $NOME_DISTRO ($FAMILIA $IMUTAVEL) model $(modelo)"

  instalar_pacotes_distro || fim_erro "Não consegui instalar o fprintd da distribuição. Instale os pacotes 'fprintd' e o módulo PAM dele e rode de novo." \
    "Could not install the distribution fprintd. Install 'fprintd' and its PAM module, then run again."

  titulo "Instalando o driver em $PREFIXO" "Installing the driver in $PREFIXO"
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
  ok "Arquivos instalados" "Files installed"

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
  systemctl daemon-reload
  systemctl restart fprintd

  titulo "Conferindo o leitor" "Checking the reader"
  r=$(testar_servico)
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
    titulo "Login com digital" "Fingerprint login"
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
  rm -f "$DROPIN" "$AJUSTE_CONF"
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

raiz_ajustar() { # limiar
  [ -e "$DROPIN" ] || fim_erro "O fprint-538d não está instalado." "fprint-538d is not installed."
  case "$1" in *[!0-9]* | '') exit 1 ;; esac
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
  systemctl daemon-reload
  systemctl restart fprintd 2>/dev/null || true
}

# ---------------------------------------------------------------------------------------------
# USER PART

como_root() { # runs this script's root part
  local bash_bin
  bash_bin=$(command -v bash)
  if [ "$(id -u)" = 0 ]; then "$bash_bin" "$SELF" --lang "$L" --interno "$@"
  elif [ "$TEM_TTY" = 1 ] && command -v sudo >/dev/null; then sudo "$bash_bin" "$SELF" --lang "$L" --interno "$@"
  elif command -v pkexec >/dev/null; then pkexec "$bash_bin" "$SELF" --lang "$L" --interno "$@"
  else sudo "$bash_bin" "$SELF" --lang "$L" --interno "$@"; fi
}

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
    titulo "Compilando o driver (pode levar 10–20 minutos)" "Building the driver (may take 10–20 minutes)"
    local fonte
    fonte=$(dirname "$SELF")
    if [ ! -x "$fonte/construir/no-conteiner.sh" ]; then
      command -v git >/dev/null || fim_erro "Preciso do 'git' para compilar." "'git' is needed to build."
      fonte=$TMPD/fonte
      git clone -q --depth 1 "https://github.com/$REPO_GH.git" "$fonte" || fim_erro "Falha ao baixar o código." "Failed to download the source."
    fi
    command -v podman >/dev/null || command -v docker >/dev/null ||
      fim_erro "Para compilar preciso do podman ou docker (o sistema não é alterado). Instale um deles e rode de novo." \
        "Building needs podman or docker (keeps the system clean). Install one and run again."
    "$fonte/construir/no-conteiner.sh" || fim_erro "A compilação falhou." "The build failed."
    arq=$fonte/dist/fprint-538d-x86_64.tar.gz
  else
    titulo "Baixando o driver" "Downloading the driver"
    arq=$TMPD/fprint-538d-x86_64.tar.gz
    if ! baixar "$URL_PACOTE" "$arq" || ! baixar "$URL_PACOTE.sha256" "$arq.sha256"; then
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
  titulo "Conferindo este computador" "Checking this computer"
  [ "$(uname -m)" = x86_64 ] || fim_erro "Só computadores x86_64 (Intel/AMD) são suportados." "Only x86_64 (Intel/AMD) computers are supported."
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
}

# --- enrollment ---------------------------------------------------------------------------------

DEDOS=(right-index-finger right-thumb left-index-finger left-thumb)
nome_dedo() {
  case "$1" in
    right-index-finger) t "indicador direito" "right index finger" ;;
    right-thumb) t "polegar direito" "right thumb" ;;
    left-index-finger) t "indicador esquerdo" "left index finger" ;;
    left-thumb) t "polegar esquerdo" "left thumb" ;;
    *) printf '%s' "$1" ;;
  esac
}
dedos_cadastrados() { fprintd-list "$USER" 2>/dev/null | sed -n 's/^ *- *#[0-9]*: *//p'; }

cadastrar() {
  titulo "Cadastro da digital" "Fingerprint enrollment"
  local ja dedo esc i
  ja=$(dedos_cadastrados)
  if [ -n "$ja" ]; then
    info "Digitais já cadastradas: $(echo $ja)" "Fingerprints already enrolled: $(echo $ja)"
    perguntar "Manter essas digitais e pular o cadastro?" "Keep them and skip enrollment?" s && return 0
  fi
  [ "$TEM_TTY" = 1 ] || { info "Cadastre depois: fprintd-enroll" "Enroll later: fprintd-enroll"; return 0; }
  dedo=${DEDOS[0]}
  if [ "$SIM" = 0 ]; then
    info "Qual dedo cadastrar?" "Which finger?"
    for i in 0 1 2 3; do printf '      %d) %s\n' $((i + 1)) "$(nome_dedo "${DEDOS[$i]}")"; done
    printf '   %s ' "$(t "Número [1]:" "Number [1]:")"
    read -r esc <&3 || esc=1
    case "$esc" in 2 | 3 | 4) dedo=${DEDOS[$((esc - 1))]} ;; esac
  fi
  cat <<EOF

   $(t "Serão 15 toques no leitor. Para ele reconhecer bem depois:" "15 touches on the reader. For good recognition later:")
     • $(t "encoste de leve, sem apertar, e levante o dedo por completo entre os toques" "touch lightly, without pressing, and lift the finger completely between touches")
     • $(t "varie a cada toque: centro, ponta, laterais, e o dedo um pouco girado para os dois lados" "vary each touch: center, tip, sides, and the finger slightly rotated both ways")
     • $(t "se pedir para repetir um toque, é normal" "being asked to repeat a touch is normal")

EOF
  esperar_enter "Aperte Enter e comece com o $(nome_dedo "$dedo")..." "Press Enter and start with your $(nome_dedo "$dedo")..."
  fprintd-delete "$USER" -f "$dedo" >/dev/null 2>&1
  if fprintd-enroll -f "$dedo"; then
    ok "Digital cadastrada" "Fingerprint enrolled"
  else
    aviso "O cadastro não terminou. Tente de novo pelas Configurações do sistema ou com: fprintd-enroll -f $dedo" \
      "Enrollment did not finish. Try again in the system Settings or with: fprintd-enroll -f $dedo"
  fi
}

principal_instalar() {
  printf '%s\n' "${C_N}fprint-538d — $(t "leitor de digital Goodix 538d" "Goodix 538d fingerprint reader")${C_0}"
  verificar
  local pam=s
  if [ -e "$PREFIXO/share/fprint-538d/VERSAO" ]; then
    info "Já instalado: será atualizado/reparado, mantendo as digitais." "Already installed: it will be updated/repaired, keeping the fingerprints."
  fi
  titulo "Opções" "Options"
  perguntar "Usar a digital para entrar no sistema, desbloquear a tela, sudo e janelas de senha? (a senha continua valendo)" \
    "Use the fingerprint to log in, unlock the screen, sudo and password dialogs? (the password keeps working)" s || pam=n

  obter_pacote
  titulo "Instalando (a senha de administrador será pedida uma vez)" "Installing (the administrator password is asked once)"
  como_root instalar "$PACOTE_DIR" "$USER" "$pam"
  local r=$?
  [ $r -eq 3 ] && exit 0
  [ $r -eq 0 ] || exit $r
  rm -rf "${XDG_CONFIG_HOME:-$HOME/.config}/fprint-538d" # left by version 0.1.0

  [ "$OPT_SEM_CADASTRO" = 1 ] || cadastrar
  titulo "Pronto!" "Done!"
  info "Desinstalar:  bash $PREFIXO/share/fprint-538d/instalar.sh --desinstalar" "Uninstall:  bash $PREFIXO/share/fprint-538d/instalar.sh --uninstall"
  info "Dedo difícil de reconhecer (calos, pele seca)? Nível de reconhecimento:  bash $PREFIXO/share/fprint-538d/instalar.sh --ajustar" \
    "Finger hard to recognise (calluses, dry skin)? Recognition level:  bash $PREFIXO/share/fprint-538d/instalar.sh --tune"
  info "Mais dedos: nas Configurações do sistema (Usuários / Digital) ou  fprintd-enroll -f left-index-finger" \
    "More fingers: in the system Settings (Users / Fingerprint) or  fprintd-enroll -f left-index-finger"
  info "Conte como foi no seu modelo: https://github.com/$REPO_GH/issues" "Tell us how it went on your model: https://github.com/$REPO_GH/issues"
  printf '\n'
}

nivel_atual() {
  local v
  v=$(sed -n 's/^FPRINT_BZ3_THRESHOLD=//p' "$AJUSTE_CONF" 2>/dev/null)
  echo "${v:-$NIVEL_PADRAO}"
}

principal_ajustar() {
  [ -e "$DROPIN" ] || fim_erro "O fprint-538d não está instalado. Instale primeiro: bash instalar.sh" \
    "fprint-538d is not installed. Install first: bash instalar.sh"
  local atual esc novo i
  atual=$(nivel_atual)
  titulo "Nível de reconhecimento" "Recognition level"
  local nomes_pt=("Rigoroso — recusa mais, inclusive o seu dedo às vezes" "Padrão (recomendado)" "Tolerante — para dedos difíceis (calos, pele seca); aceita com nota menor")
  local nomes_en=("Strict — rejects more, sometimes your own finger too" "Default (recommended)" "Tolerant — for hard fingers (calluses, dry skin); accepts lower scores")
  for i in 0 1 2; do
    printf '      %d) %s  [%s]%s\n' $((i + 1)) "$(t "${nomes_pt[$i]}" "${nomes_en[$i]}")" "${NIVEIS[$i]}" \
      "$([ "${NIVEIS[$i]}" = "$atual" ] && t "  ← atual" "  ← current")"
  done
  info "Nos testes, dedos errados tiraram no máximo 51; o nível Tolerante (55) ainda fica acima disso." \
    "In the tests, wrong fingers scored at most 51; the Tolerant level (55) is still above that."
  [ "$TEM_TTY" = 1 ] || fim_erro "Rode num terminal para escolher." "Run it in a terminal to choose."
  printf '   %s ' "$(t "Número (Enter = manter):" "Number (Enter = keep):")"
  read -r esc <&3 || esc=""
  case "$esc" in 1 | 2 | 3) novo=${NIVEIS[$((esc - 1))]} ;; *) info "Nada mudou." "Nothing changed."; return 0 ;; esac
  [ "$novo" = "$atual" ] && { info "Nada mudou." "Nothing changed."; return 0; }
  como_root ajustar "$novo" || exit 1
  ok "Nível de reconhecimento: $novo (vale a partir do próximo toque)" "Recognition level: $novo (applies from the next touch)"
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
ACAO=instalar OPT_PACOTE="" OPT_COMPILAR=0 OPT_SEM_CADASTRO=0
while [ $# -gt 0 ]; do
  case "$1" in
    --desinstalar | --uninstall) ACAO=desinstalar ;;
    --ajustar | --tune) ACAO=ajustar ;;
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
    -h | --help | --ajuda) sed -n '2,16p' "$SELF"; exit 0 ;;
    *) fim_erro "Opção desconhecida: $1" "Unknown option: $1" ;;
  esac
  shift
done

if [ "$(id -u)" = 0 ]; then
  fim_erro "Rode como usuário normal, sem sudo: bash instalar.sh (a senha será pedida quando precisar)." \
    "Run as your normal user, without sudo: bash instalar.sh (the password is asked when needed)."
fi
TMPD=$(mktemp -d "${TMPDIR:-/tmp}/fprint-538d.XXXXXX")
trap 'rm -rf "$TMPD"' EXIT

case "$ACAO" in
  instalar) principal_instalar ;;
  desinstalar) principal_desinstalar ;;
  ajustar) principal_ajustar ;;
esac
