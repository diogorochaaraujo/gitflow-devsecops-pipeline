#!/usr/bin/env bash
# Aplica a governanca da esteira numa ORGANIZACAO a partir de governance/:
#   1. propriedades customizadas (fornecedor, pipeline, criticidade)
#   2. rulesets de org: branches, arquivos da plataforma (push), tags
#   3. politica de Actions: allowlist, SHA obrigatorio, token so leitura, forks
#   4. OIDC: job_workflow_ref no `sub` (confianca presa ao workflow da plataforma)
#
# SIMULA POR PADRAO: mostra cada chamada e o corpo. APLICAR=1 executa.
#
# uso: [APLICAR=1] scripts/governance/apply-org.sh <org> <time-da-plataforma> <app-id-de-release>
# requer: gh com admin:org. Rulesets de org e push rules: plano Team ou superior.
set -euo pipefail

org=${1:?uso: apply-org.sh <org> <time-da-plataforma> <app-id-de-release>}
team=${2:?slug do time da plataforma (bypass das regras de arquivos)}
app_id=${3:?id da GitHub App que cria tags de versao}
gov="$(cd "$(dirname "$0")/../../governance" && pwd)"
apply=${APLICAR:-0}

call() { # metodo caminho [arquivo-json]
  local method=$1 path=$2 body=${3:-}
  if [ "$apply" != 1 ]; then
    printf '\n[simulacao] %s %s\n' "$method" "$path"
    [ -n "$body" ] && jq . <<<"$body"
    return 0
  fi
  printf '\n%s %s\n' "$method" "$path"
  if [ -n "$body" ]; then gh api -X "$method" "$path" --input - --silent <<<"$body"
  else gh api -X "$method" "$path" --silent; fi
}

upsert_ruleset() {
  local body=$1 name id=""
  name=$(jq -r .name <<<"$body")
  [ "$apply" = 1 ] && id=$(gh api "orgs/$org/rulesets" --jq ".[] | select(.name == \"$name\") | .id")
  if [ -n "$id" ]; then call PUT "orgs/$org/rulesets/$id" "$body"
  else call POST "orgs/$org/rulesets" "$body"; fi
}

team_id=$( [ "$apply" = 1 ] && gh api "orgs/$org/teams/$team" --jq .id || echo "<id de $team>")

echo "== 1. propriedades customizadas"
call PATCH "orgs/$org/properties/schema" "$(jq -c '{properties: .}' "$gov/custom-properties.json")"

echo "== 2. rulesets"
upsert_ruleset "$(jq -c . "$gov/rulesets/branches.json")"
upsert_ruleset "$(jq -c --arg t "$team_id" '(.bypass_actors[] | select(.actor_id == "__PLATFORM_TEAM_ID__") | .actor_id) |= ($t | tonumber? // $t)' "$gov/rulesets/arquivos-plataforma.json")"
upsert_ruleset "$(jq -c --arg a "$app_id" '(.bypass_actors[] | select(.actor_id == "__RELEASE_APP_ID__") | .actor_id) |= ($a | tonumber? // $a)' "$gov/rulesets/tags.json")"

echo "== 3. politica de Actions"
policy="$gov/actions-policy.json"
call PUT "orgs/$org/actions/permissions" "$(jq -c '.permissions' "$policy")"
call PUT "orgs/$org/actions/permissions/selected-actions" "$(jq -c '.selected_actions' "$policy")"
call PUT "orgs/$org/actions/permissions/workflow" "$(jq -c '.workflow_permissions' "$policy")"
call PUT "orgs/$org/actions/permissions/fork-pr-workflows-private-repos" "$(jq -c '.fork_pr_workflows_private_repos' "$policy")"

echo "== 4. OIDC: job_workflow_ref no sub"
call PUT "orgs/$org/actions/oidc/customization/sub" '{"include_claim_keys":["repo","context","job_workflow_ref"]}'

[ "$apply" = 1 ] || printf '\nNada foi alterado. Para aplicar: APLICAR=1 %s %s %s %s\n' "$0" "$org" "$team" "$app_id"
