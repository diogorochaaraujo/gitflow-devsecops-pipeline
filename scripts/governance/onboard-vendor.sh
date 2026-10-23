#!/usr/bin/env bash
# Entrada (ou saida) de um fornecedor numa organizacao:
#   - time `vnd-<fornecedor>`, fechado, com permissao `push` (write) so nos
#     repositorios do contrato -- nunca maintain/admin;
#   - propriedade `fornecedor=<nome>` nos repositorios (regras, OIDC e relatorios);
#   - saida (REMOVER=1): tira o time dos repositorios e limpa a propriedade.
#
# SIMULA POR PADRAO. APLICAR=1 executa.
#
# uso: [APLICAR=1] [REMOVER=1] scripts/governance/onboard-vendor.sh <org> <fornecedor> <repo> [repo...]
set -euo pipefail

org=${1:?uso: onboard-vendor.sh <org> <fornecedor> <repo>...}
vendor=${2:?nome do fornecedor (minusculas, sem espaco)}
shift 2
[ $# -gt 0 ] || { echo "informe ao menos um repositorio" >&2; exit 1; }
team="vnd-$vendor"
apply=${APLICAR:-0}
remove=${REMOVER:-0}

run() { if [ "$apply" = 1 ]; then echo "+ $*"; "$@"; else echo "[simulacao] $*"; fi; }

if [ "$remove" != 1 ]; then
  if [ "$apply" = 1 ] && gh api "orgs/$org/teams/$team" --silent 2>/dev/null; then
    echo "time $team ja existe"
  else
    run gh api -X POST "orgs/$org/teams" -f name="$team" -f privacy=closed \
      -f description="Fornecedor $vendor: write nos repositorios do contrato" --silent
  fi
fi

for r in "$@"; do
  if [ "$remove" = 1 ]; then
    run gh api -X DELETE "orgs/$org/teams/$team/repos/$org/$r" --silent
    run gh api -X PATCH "orgs/$org/properties/values" --input - --silent \
      <<<"{\"repository_names\":[\"$r\"],\"properties\":[{\"property_name\":\"fornecedor\",\"value\":null}]}"
  else
    run gh api -X PUT "orgs/$org/teams/$team/repos/$org/$r" -f permission=push --silent
    run gh api -X PATCH "orgs/$org/properties/values" --input - --silent \
      <<<"{\"repository_names\":[\"$r\"],\"properties\":[{\"property_name\":\"fornecedor\",\"value\":\"$vendor\"},{\"property_name\":\"pipeline\",\"value\":\"managed\"}]}"
  fi
done

cat <<EOF

Depois, fora do script:
  - membros do fornecedor entram no time $team (com SSO/2FA da organizacao);
  - CODEOWNERS do repositorio: caminhos sensiveis com o time do cliente;
  - Environments HMG/PRD: revisores do cliente, nunca o time $team.
EOF
[ "$apply" = 1 ] || echo "Nada foi alterado. Para aplicar: APLICAR=1 $0 $org $vendor $*"
