#!/usr/bin/env bash
# Calcula a versao do artefato a partir da ultima tag de release (X.Y.Z).
#
#   snapshot -> <proxima minor>-<run>-SNAPSHOT   (imagem de desenvolvimento, sem tag git)
#   release  -> <proxima>-<run>                  (release candidate, vira tag git)
#
# O tipo de incremento vem do segundo argumento:
#   Major | Minor | Patch -> explicito (label do PR, modelo gitflow)
#   auto                  -> Conventional Commits desde a ultima release (modelo trunk):
#                            `tipo!:` ou `BREAKING CHANGE` = Major, `feat` = Minor, resto = Patch
#
# A versao final X.Y.Z nao e calculada aqui: a promocao a deriva da RC
# aprovada, para que o artefato promovido seja exatamente o que foi testado.
#
# uso: version.sh <snapshot|release> [Major|Minor|Patch|auto] [ref]
set -euo pipefail

mode=${1:?uso: version.sh <snapshot|release> [Major|Minor|Patch|auto] [ref]}
bump=${2:-Minor}
ref=${3:-HEAD}
run=${GITHUB_RUN_NUMBER:-0}

last=$(git tag --list | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1 || true)

if [ "$bump" = auto ]; then
  range=$ref; [ -n "$last" ] && range="$last..$ref"
  log=$(git log --format='%s%n%b%n--' "$range")
  if grep -qE '^[a-z]+(\([^)]*\))?!:|^BREAKING[ -]CHANGE:' <<<"$log"; then bump=Major
  elif grep -qE '^feat(\([^)]*\))?:' <<<"$log"; then bump=Minor
  else bump=Patch
  fi
fi
[ "$mode" = snapshot ] && bump=Minor

last=${last:-0.0.0}
IFS=. read -r major minor patch <<<"$last"
case "$bump" in
  Major) next="$((major + 1)).0.0" ;;
  Minor) next="$major.$((minor + 1)).0" ;;
  Patch) next="$major.$minor.$((patch + 1))" ;;
  *) echo "tipo de release invalido: $bump" >&2; exit 1 ;;
esac

case "$mode" in
  snapshot) version="$next-$run-SNAPSHOT" ;;
  release)  version="$next-$run" ;;
  *) echo "modo invalido: $mode" >&2; exit 1 ;;
esac

echo "Ultima release: $last | tipo: $bump | versao: $version" >&2
echo "$version"
