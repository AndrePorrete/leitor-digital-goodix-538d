#!/usr/bin/env bash
# Teste guiado da digital: pede cada dedo, verifica e anota resultado + nota.
# Uso: ~/.cache/instalar-goodix/testar.sh        (sem sudo)
set -u
DEDOS=("CERTO: indicador direito" "ERRADO: médio direito" "CERTO: indicador direito" "ERRADO: polegar direito"
       "CERTO: indicador direito" "ERRADO: médio esquerdo" "CERTO: indicador direito" "ERRADO: anelar direito"
       "CERTO: indicador direito" "ERRADO: médio direito" "CERTO: indicador direito" "ERRADO: polegar direito"
       "CERTO: indicador direito" "ERRADO: indicador esquerdo" "CERTO: indicador direito" "ERRADO: médio esquerdo")
LOG="$HOME/.cache/instalar-goodix/teste-$(date +%H%M).txt"
echo "Use SEMPRE o dedo pedido. Se o dedo errado não for lido, não troque: em 25 s passa sozinho."; echo
printf "%-28s %-16s %s\n" "DEDO" "RESULTADO" "MAIOR NOTA (mín. p/ aceitar 60)" | tee "$LOG"
for d in "${DEDOS[@]}"; do
  echo
  read -rp ">>> Próximo: $d — aperte Enter e encoste esse dedo quando pedir " _
  ini=$(date '+%Y-%m-%d %H:%M:%S'); t0=$(date +%s.%N)
  res=$(timeout 25 fprintd-verify -f any 2>&1 | grep -o 'verify-[a-z-]*' | tail -1)
  sleep 0.5
  nota=$(journalctl -u fprintd --since "$ini" --no-pager -o cat 2>/dev/null | grep -o 'sigfm score [0-9]*' | awk '{if($3>m)m=$3} END{print m+0}')
  [ -z "$res" ] && res="sem leitura"
  case "$res" in verify-match) r="ACEITO";; verify-no-match) r="recusado";; *) r="$res";; esac
  printf "%-28s %-16s %s\n" "$d" "$r" "$nota" | tee -a "$LOG"
  echo "$t0 $(date +%s.%N) $d" >> "${LOG%.txt}.tempos"
done
echo; echo "Tabela salva em $LOG — cole aqui ou só me avise."
