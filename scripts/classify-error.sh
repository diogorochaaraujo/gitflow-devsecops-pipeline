#!/usr/bin/env bash
# Classifica uma falha pelas regras de scripts/error-hints.tsv (a primeira que casar).
# Entrada: texto do erro em stdin. Saida: "<classe>\t<o que fazer>".
#
# uso: classify-error.sh [error-hints.tsv] < erro.txt
set -euo pipefail

hints=${1:-"$(dirname "$0")/error-hints.tsv"}
text=$(cat)
while IFS=$'\t' read -r regex class hint; do
  case "$regex" in ''|'#'*) continue ;; esac
  if grep -qiE -- "$regex" <<<"$text"; then printf '%s\t%s\n' "$class" "$hint"; exit 0; fi
done < "$hints"
printf 'nao classificado\tLer o log do job; nenhuma regra conhecida casou.\n'
