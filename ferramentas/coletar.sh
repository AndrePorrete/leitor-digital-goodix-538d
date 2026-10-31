#!/usr/bin/env bash
# Coleta guiada de toques do leitor Goodix 538d, separada por dedo.
# Uso: sudo ~/.cache/instalar-goodix/coletar.sh
set -u
H="$(cd "$(dirname "$0")" && pwd)"
OUT="$H/coleta-$(date +%H%M)"
[ "$(id -u)" -eq 0 ] || { echo "Rode com sudo: sudo $0"; exit 1; }

systemctl stop fprintd
trap 'systemctl start fprintd; chown -R "${SUDO_USER:-porrete}": "$OUT" 2>/dev/null' EXIT

export GOODIX53XD_DAC_OFFSET=8
export G_MESSAGES_DEBUG=
"$H/coletar" "$OUT" indicador-direito:16 medio-direito:10 medio-esquerdo:8 anelar-direito:5 indicador-esquerdo:5
