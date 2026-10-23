#!/usr/bin/env bash
# Migracao que ja saiu numa release nunca muda: o banco de producao ja a aplicou,
# e o Flyway recusaria o checksum novo (ou pior, ambientes divergiriam).
# Correcao de migracao e sempre uma migracao NOVA.
#
# Compara o commit atual com a ultima release (X.Y.Z) e falha se algum arquivo
# existente numa pasta de migracoes foi alterado, renomeado ou apagado.
#
# uso: check-migrations.sh [deploy-config.yml] [ref]
set -euo pipefail

file=${1:-.github/configs/deploy-config.yml}
ref=${2:-HEAD}

dirs=$(yq '[.artifacts[] | select(.driver == "flyway") | (.flyway.locations // "db/migrations")] | unique | .[]' "$file")
[ -n "$dirs" ] || { echo "sem artefato flyway: nada a conferir"; exit 0; }

last=$(git tag --list | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1 || true)
[ -n "$last" ] || { echo "sem release anterior: nenhuma migracao publicada ainda"; exit 0; }

status=0
while IFS= read -r dir; do
  changed=$(git diff --name-status "$last" "$ref" -- "$dir" | grep -vE '^A' || true)
  if [ -n "$changed" ]; then
    status=1
    echo "::error::Migracao publicada em $last foi alterada em $dir. Crie uma migracao nova em vez de editar:"
    while IFS= read -r line; do echo "  $line"; done <<<"$changed"
  fi
done <<<"$dirs"
[ "$status" -eq 0 ] && echo "migracoes: nenhuma alteracao desde $last (so inclusoes)"
exit "$status"
