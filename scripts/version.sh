#!/usr/bin/env bash
# Calcula a versao do artefato a partir da ultima tag de release (X.Y.Z).
#
#   snapshot -> <proxima minor>-<run>-SNAPSHOT   (imagem de desenvolvimento, sem tag git)
#   release  -> <proxima pelo label>-<run>       (release candidate, vira tag git)
#
# A versao final X.Y.Z nao e calculada aqui: o Finish Release a deriva da RC
# aprovada, para que o artefato promovido seja exatamente o que foi testado.
#
# uso: version.sh <snapshot|release> [Major|Minor|Patch]
set -euo pipefail

mode=${1:?uso: version.sh <snapshot|release> [Major|Minor|Patch]}
bump=${2:-Minor}
run=${GITHUB_RUN_NUMBER:-0}

last=$(git tag --list | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1 || true)
last=${last:-0.0.0}
IFS=. read -r major minor patch <<<"$last"

[ "$mode" = snapshot ] && bump=Minor
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
