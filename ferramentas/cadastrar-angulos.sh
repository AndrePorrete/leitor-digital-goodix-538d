#!/usr/bin/env bash
# Segundo cadastro do INDICADOR DIREITO, em ângulos variados (vaga "right-thumb" é só um rótulo).
# Uso: ~/.cache/instalar-goodix/cadastrar-angulos.sh   (sem sudo)
set -u
clear
cat <<'TXT'
==============================================================
  USE SOMENTE O INDICADOR DIREITO EM TODOS OS TOQUES
  (o sistema chama a vaga de "right-thumb", mas ignore o nome)
==============================================================
  Encoste de leve, sem apertar. A cada toque, gire um pouco:
    toques 1-4 : dedo reto
    toques 5-8 : inclinado para a esquerda
    toques 9-12: inclinado para a direita
    toques 13-15: de lado / de ponta-cabeça
TXT
read -rp "Aperte Enter para começar " _
fprintd-delete "$USER" -f right-thumb >/dev/null 2>&1
fprintd-enroll -f right-thumb
echo; fprintd-list "$USER" | tail -n +4
