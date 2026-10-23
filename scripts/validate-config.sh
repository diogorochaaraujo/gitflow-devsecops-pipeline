#!/usr/bin/env bash
# Valida pipeline.yml e deploy-config.yml contra os schemas da plataforma.
# Um erro de digitacao (chave inexistente, stack errada) para aqui, em segundos,
# e nao no meio do build ou do deploy.
#
# uso: validate-config.sh [raiz-da-app]   (schemas lidos ao lado deste script)
set -euo pipefail

root=${1:-.}
schemas="$(cd "$(dirname "$0")/../schemas" && pwd)"
tool="check-jsonschema==0.38.2"

if command -v uvx >/dev/null; then run=(uvx --quiet --from "$tool" check-jsonschema)
else run=(pipx run --quiet --spec "$tool" check-jsonschema)
fi

status=0
"${run[@]}" --schemafile "$schemas/pipeline.schema.json" "$root/pipeline.yml" || status=1
"${run[@]}" --schemafile "$schemas/deploy-config.schema.json" "$root/.github/configs/deploy-config.yml" || status=1
if [ "$status" -ne 0 ]; then
  echo "::error::Configuracao invalida: veja acima o campo e a regra violada (docs/04-config-as-code.md)."
fi
exit "$status"
