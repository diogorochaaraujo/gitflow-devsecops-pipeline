#!/usr/bin/env bash
# Prepara um repositorio para a esteira, uma vez: branch de integracao, labels
# de release, ambientes (PRD com aprovacao), regras de branch e de tag e a
# permissao do GITHUB_TOKEN para abrir o PR de back-merge.
#
# No modelo de referencia isso e sincronizado a cada execucao do pipeline;
# aqui e um passo de bootstrap idempotente (docs/07-melhorias.md, item 2).
#
# uso: scripts/bootstrap-repo.sh <owner/repo> [revisor-de-producao]
# requer: gh autenticado com permissao de admin no repositorio
set -euo pipefail

repo=${1:?uso: bootstrap-repo.sh <owner/repo> [revisor]}
reviewer=${2:-$(gh api user --jq .login)}
integration=${INTEGRATION_BRANCH:-dsv}

step() { printf '\n== %s\n' "$*"; }
warn() { printf 'AVISO: %s\n' "$*" >&2; }

step "branch de integracao: $integration"
if ! gh api "repos/$repo/branches/$integration" --silent 2>/dev/null; then
  main_sha=$(gh api "repos/$repo/git/ref/heads/main" --jq .object.sha)
  gh api -X POST "repos/$repo/git/refs" -f ref="refs/heads/$integration" -f sha="$main_sha" --silent
  echo "criada a partir de main ($main_sha)"
else
  echo "ja existe"
fi

step "labels de release"
gh label create Release-Major -R "$repo" --color 0E8A16 --description "Mudanca incompativel" --force
gh label create Release-Minor -R "$repo" --color FBCA04 --description "Funcionalidade compativel" --force
gh label create Release-Patch -R "$repo" --color B60205 --description "Correcao compativel" --force

step "ambientes"
for env in DSV TST HMG; do
  gh api -X PUT "repos/$repo/environments/$env" --silent && echo "$env"
done
reviewer_id=$(gh api "users/$reviewer" --jq .id)
if gh api -X PUT "repos/$repo/environments/PRD" --input - --silent <<EOF
{"reviewers":[{"type":"User","id":$reviewer_id}],"prevent_self_review":false}
EOF
then
  echo "PRD (aprovacao: $reviewer)"
else
  warn "PRD sem revisor: em repositorio privado de conta pessoal a regra exige plano pago"
  gh api -X PUT "repos/$repo/environments/PRD" --silent
fi

step "permissao do GITHUB_TOKEN para criar PR (back-merge)"
gh api -X PUT "repos/$repo/actions/permissions/workflow" \
  -f default_workflow_permissions=read -F can_approve_pull_request_reviews=true --silent

step "regra da main: so por PR, sem force push, sem delecao, Release Validation verde e branch atualizada"
gh api -X POST "repos/$repo/rulesets" --input - --silent <<'EOF' || warn "ruleset da main nao criado (ja existe ou plano nao permite)"
{
  "name": "main-protection",
  "target": "branch",
  "enforcement": "active",
  "conditions": {"ref_name": {"include": ["refs/heads/main"], "exclude": []}},
  "rules": [
    {"type": "deletion"},
    {"type": "non_fast_forward"},
    {"type": "pull_request", "parameters": {
      "required_approving_review_count": 0,
      "dismiss_stale_reviews_on_push": true,
      "require_code_owner_review": false,
      "require_last_push_approval": false,
      "required_review_thread_resolution": false}},
    {"type": "required_status_checks", "parameters": {
      "strict_required_status_checks_policy": true,
      "required_status_checks": [{"context": "Start Release / Release Validation"}]}}
  ]
}
EOF

step "regra de tags: imutaveis (nao se apaga nem se move uma versao publicada)"
gh api -X POST "repos/$repo/rulesets" --input - --silent <<'EOF' || warn "ruleset de tags nao criado (ja existe ou plano nao permite)"
{
  "name": "tags-imutaveis",
  "target": "tag",
  "enforcement": "active",
  "conditions": {"ref_name": {"include": ["~ALL"], "exclude": []}},
  "rules": [{"type": "deletion"}, {"type": "update"}]
}
EOF

step "pronto"
echo "Proximo passo: docs/06-laboratorio.md"
