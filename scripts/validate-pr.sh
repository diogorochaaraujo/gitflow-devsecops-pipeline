#!/usr/bin/env bash
# Validacoes do PR de release, antes de gastar runner com build:
#   1. a branch do PR contem tudo o que esta na base (zero commits atras);
#   2. versionamento por label: exatamente um Release-Major|Minor|Patch.
#
# A regra 1 garante que a arvore mergeada na main seja identica a arvore que
# gerou a RC -- e o que permite promover o artefato sem reconstruir.
#
# env: BASE_REF HEAD_SHA LABELS(JSON array de nomes) VERSIONING(label|conventional)
# saida: release-type=<Major|Minor|Patch|auto> em $GITHUB_OUTPUT
set -euo pipefail

git fetch --quiet origin "$BASE_REF"
behind=$(git rev-list --count "$HEAD_SHA..origin/$BASE_REF")
if [ "$behind" -gt 0 ]; then
  echo "::error::A branch do PR esta $behind commit(s) atras de $BASE_REF. Faca merge de $BASE_REF na branch do PR e envie de novo."
  exit 1
fi

if [ "${VERSIONING:-label}" = conventional ]; then
  type=auto
else
  release_labels=$(jq -r '.[]' <<<"$LABELS" | grep -E '^Release-(Major|Minor|Patch)$' || true)
  count=$(grep -c . <<<"$release_labels" || true)
  if [ "$count" -ne 1 ]; then
    echo "::error::O PR precisa de exatamente um label Release-Major, Release-Minor ou Release-Patch (encontrado(s): $count)."
    exit 1
  fi
  type=${release_labels#Release-}
fi

echo "Branch em dia com $BASE_REF; tipo de release: $type"
echo "release-type=$type" >> "${GITHUB_OUTPUT:-/dev/null}"
