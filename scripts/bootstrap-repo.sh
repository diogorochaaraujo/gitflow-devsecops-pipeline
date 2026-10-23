#!/usr/bin/env bash
# Prepara UM repositorio para a esteira (conta pessoal ou org sem regras de
# organizacao): branch de integracao, labels, Environments, regras de branch e
# de tag e permissao do GITHUB_TOKEN para abrir PR. Idempotente: cria ou atualiza.
#
# Numa organizacao, prefira as regras de org (scripts/governance/apply-org.sh):
# valem para todos os repositorios e o time da aplicacao nao consegue alterar.
#
# Ambientes, aprovadores e tempo de espera vem do deploy-config.yml
# (envs.<ENV>.reviewers / waitTimer / preventSelfReview): a regra de quem aprova
# e versionada e revisada por PR, e aplicada aqui -- nao a cada execucao do pipeline.
#
# Separacao de funcoes por padrao: o PR para a main exige MAIN_REVIEWS aprovacoes
# (padrao 1) e quem disparou o deploy nao o aprova. Com uma pessoa so (laboratorio
# solo): MAIN_REVIEWS=0 e envs.<ENV>.preventSelfReview: false.
#
# uso: [MAIN_REVIEWS=n] scripts/bootstrap-repo.sh <owner/repo> [deploy-config.yml]
# requer: gh autenticado com permissao de admin no repositorio
set -euo pipefail

repo=${1:?uso: bootstrap-repo.sh <owner/repo> [deploy-config.yml]}
config=${2:-.github/configs/deploy-config.yml}
integration=${INTEGRATION_BRANCH:-dsv}
main_reviews=${MAIN_REVIEWS:-1}

step() { printf '\n== %s\n' "$*"; }
warn() { printf 'AVISO: %s\n' "$*" >&2; }

# cria ou atualiza um ruleset do repositorio pelo nome
upsert_ruleset() {
  local body=$1 name id
  name=$(jq -r .name <<<"$body")
  id=$(gh api "repos/$repo/rulesets" --jq ".[] | select(.name == \"$name\") | .id" 2>/dev/null || true)
  if [ -n "$id" ]; then
    gh api -X PUT "repos/$repo/rulesets/$id" --input - --silent <<<"$body" && echo "$name: atualizado"
  else
    gh api -X POST "repos/$repo/rulesets" --input - --silent <<<"$body" && echo "$name: criado"
  fi || warn "$name nao aplicado (plano nao permite neste tipo de repositorio?)"
}

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
echo "Release-Major, Release-Minor, Release-Patch"

step "ambientes (de $config)"
envs=$(yq -o=json '[((.accounts // {}) | keys), ((.envs // {}) | keys)] | flatten | unique' "$config" | jq -r '.[]')
for env in $envs; do
  reviewers=$(yq -o=json -I=0 ".envs.$env.reviewers // []" "$config")
  wait_min=$(yq ".envs.$env.waitTimer // 0" "$config")
  # `// true` trataria o false explicito como ausente
  self=$(yq ".envs.$env.preventSelfReview" "$config"); [ "$self" = false ] || self=true
  ids='[]'
  for row in $(jq -c '.[]' <<<"$reviewers"); do
    if user=$(jq -er '.user // empty' <<<"$row"); then
      id=$(gh api "users/$user" --jq .id); ids=$(jq -c --argjson id "$id" '. + [{"type":"User","id":$id}]' <<<"$ids")
    elif team=$(jq -er '.team // empty' <<<"$row"); then
      id=$(gh api "orgs/${team%%/*}/teams/${team#*/}" --jq .id); ids=$(jq -c --argjson id "$id" '. + [{"type":"Team","id":$id}]' <<<"$ids")
    fi
  done
  body=$(jq -nc --argjson r "$ids" --argjson w "$wait_min" --argjson s "$self" \
    'if ($r | length) > 0 then {reviewers: $r, wait_timer: $w, prevent_self_review: $s} else {wait_timer: $w} end')
  if gh api -X PUT "repos/$repo/environments/$env" --input - --silent <<<"$body"; then
    echo "$env: $(jq -r '[.[] | (.user // .team)] | if length > 0 then "aprovacao: " + join(", ") else "sem aprovacao" end' <<<"$reviewers")$([ "$wait_min" -gt 0 ] && echo ", espera ${wait_min}min")$([ "$reviewers" != "[]" ] && [ "$self" = true ] && echo ", sem autoaprovacao")"
  else
    warn "$env: regra de aprovacao nao aplicada (repositorio privado fora do Enterprise?)"
    gh api -X PUT "repos/$repo/environments/$env" --silent
  fi
done

step "permissao do GITHUB_TOKEN para criar PR (back-merge, GitOps)"
gh api -X PUT "repos/$repo/actions/permissions/workflow" \
  -f default_workflow_permissions=read -F can_approve_pull_request_reviews=true --silent
echo "ok"

step "regras (PR para a main: $main_reviews aprovacao(oes))"
upsert_ruleset '{
  "name": "main-protection",
  "target": "branch",
  "enforcement": "active",
  "conditions": {"ref_name": {"include": ["refs/heads/main"], "exclude": []}},
  "rules": [
    {"type": "deletion"},
    {"type": "non_fast_forward"},
    {"type": "pull_request", "parameters": {
      "required_approving_review_count": '"$main_reviews"',
      "dismiss_stale_reviews_on_push": true,
      "require_code_owner_review": false,
      "require_last_push_approval": false,
      "required_review_thread_resolution": false,
      "allowed_merge_methods": ["merge"]}},
    {"type": "required_status_checks", "parameters": {
      "strict_required_status_checks_policy": true,
      "required_status_checks": [{"context": "Pipeline / Gate"}]}}
  ]
}'
upsert_ruleset '{
  "name": "tags-imutaveis",
  "target": "tag",
  "enforcement": "active",
  "conditions": {"ref_name": {"include": ["~ALL"], "exclude": []}},
  "rules": [{"type": "deletion"}, {"type": "update"}]
}'

step "pronto"
echo "Proximo passo: docs/06-laboratorio.md"
