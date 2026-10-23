#!/usr/bin/env bash
# Validacoes do PR de release, antes de gastar runner com build:
#   1. o evento e de pull request;
#   2. a branch do PR contem tudo o que esta na base (zero commits atras);
#   3. existe exatamente um label Release-Major|Minor|Patch.
#
# A regra 2 garante que a arvore mergeada na main seja identica a arvore que
# gerou a RC -- e o que permite promover o artefato sem reconstruir.
#
# env: GITHUB_EVENT_NAME, BASE_REF, HEAD_SHA, LABELS (JSON array de nomes)
# saida: release-type=<Major|Minor|Patch> em $GITHUB_OUTPUT
set -euo pipefail

if [ "$GITHUB_EVENT_NAME" != pull_request ]; then
  echo "::error::Start Release so roda em evento de pull request (recebido: $GITHUB_EVENT_NAME)."
  exit 1
fi

git fetch --quiet origin "$BASE_REF"
behind=$(git rev-list --count "$HEAD_SHA..origin/$BASE_REF")
if [ "$behind" -gt 0 ]; then
  echo "::error::A branch do PR esta $behind commit(s) atras de $BASE_REF. Faca merge de $BASE_REF na branch do PR e envie de novo."
  exit 1
fi

release_labels=$(jq -r '.[]' <<<"$LABELS" | grep -E '^Release-(Major|Minor|Patch)$' || true)
count=$(grep -c . <<<"$release_labels" || true)
if [ "$count" -ne 1 ]; then
  echo "::error::O PR precisa de exatamente um label Release-Major, Release-Minor ou Release-Patch (encontrado(s): $count)."
  exit 1
fi

type=${release_labels#Release-}
echo "Branch em dia com $BASE_REF; tipo de release: $type"
echo "release-type=$type" >> "$GITHUB_OUTPUT"
