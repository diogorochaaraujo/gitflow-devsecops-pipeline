#!/usr/bin/env bash
# Testes dos scripts da plataforma. Sem rede, sem GitHub: so git, jq e yq.
# uso: scripts/tests/run.sh
set -uo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
s="$root/scripts"
pass=0 fail=0
check() { # nome esperado obtido
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); printf 'FALHOU %s\n  esperado: %s\n  obtido:   %s\n' "$1" "$2" "$3"; fi
}

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
cd "$work" || exit 1
git init -q -b main && git config user.email t@t && git config user.name t
commit() { git commit -q --allow-empty -m "$1"; }

# ---------- version.sh ----------
commit "chore: inicio"
check "snapshot sem tags" "0.1.0-7-SNAPSHOT" "$(GITHUB_RUN_NUMBER=7 "$s/version.sh" snapshot 2>/dev/null)"
git tag 1.4.2; git tag 1.4.2-9; git tag 1.10.0-3
check "label Major" "2.0.0-12" "$(GITHUB_RUN_NUMBER=12 "$s/version.sh" release Major 2>/dev/null)"
check "label Minor" "1.5.0-12" "$(GITHUB_RUN_NUMBER=12 "$s/version.sh" release Minor 2>/dev/null)"
check "label Patch" "1.4.3-12" "$(GITHUB_RUN_NUMBER=12 "$s/version.sh" release Patch 2>/dev/null)"
commit "fix: corrige rota"
check "auto fix -> Patch" "1.4.3-1" "$(GITHUB_RUN_NUMBER=1 "$s/version.sh" release auto 2>/dev/null)"
commit "feat(api): campo novo"
check "auto feat -> Minor" "1.5.0-1" "$(GITHUB_RUN_NUMBER=1 "$s/version.sh" release auto 2>/dev/null)"
commit "feat!: remove rota antiga"
check "auto ! -> Major" "2.0.0-1" "$(GITHUB_RUN_NUMBER=1 "$s/version.sh" release auto 2>/dev/null)"
git tag 2.0.0; git commit -q --allow-empty -m "refactor: x" -m "BREAKING CHANGE: contrato novo"
check "auto BREAKING CHANGE no corpo -> Major" "3.0.0-1" "$(GITHUB_RUN_NUMBER=1 "$s/version.sh" release auto 2>/dev/null)"
git tag 1.10.0
check "sort -V (1.10 < 2.0)" "2.1.0-5-SNAPSHOT" "$(GITHUB_RUN_NUMBER=5 "$s/version.sh" snapshot 2>/dev/null)"
GITHUB_RUN_NUMBER=1 "$s/version.sh" release Bogus >/dev/null 2>&1; check "tipo invalido recusado" "1" "$?"

# ---------- resolve.sh ----------
gitflow='{"flow":{"model":"gitflow","integrationBranch":"dsv","environments":{"snapshot":["DSV"],"candidate":["HMG"],"release":["PRD"]}}}'
trunk='{"flow":{"model":"trunk","environments":{"candidate":["DSV","HMG"],"release":["PRD"]}}}'
route() { # pipeline evento ref base acao merged ator -> "stage build stamp pre promote post back publish"
  PIPELINE=$1 EVENT=$2 REF_NAME=$3 BASE_REF=$4 PR_ACTION=$5 PR_MERGED=$6 ACTOR=${7:-dev} "$s/resolve.sh" \
    | awk -F= '/^(stage|build|stamp|pre-envs|promote|post-envs|back-merge|publish)=/{printf "%s ", ($2==""?"-":$2)}' | sed 's/ $//'
}
check "gitflow push feature"     "snapshot true false - false - false true"       "$(route "$gitflow" push TASK-1 "" "" "")"
check "gitflow push dsv"         "snapshot true false DSV false - false true"     "$(route "$gitflow" push dsv "" "" "")"
check "gitflow push dsv por bot" "snapshot true false - false - false false"      "$(route "$gitflow" push dsv "" "" "" 'dependabot[bot]')"
check "gitflow push main"        "none false false - false - false true"          "$(route "$gitflow" push main "" "" "")"
check "gitflow PR->main aberto"  "candidate true true HMG false - false true"     "$(route "$gitflow" pull_request dsv main opened false)"
check "gitflow PR->main label"   "candidate true true HMG false - false true"     "$(route "$gitflow" pull_request dsv main labeled false)"
check "gitflow PR->main merged"  "promote false false - true PRD true true"       "$(route "$gitflow" pull_request dsv main closed true)"
check "gitflow PR->main fechado" "none false false - false - false true"          "$(route "$gitflow" pull_request dsv main closed false)"
check "gitflow PR->dsv"          "none false false - false - false true"          "$(route "$gitflow" pull_request TASK-1 dsv opened false)"
check "trunk PR->main"           "verify true false - false - false true"         "$(route "$trunk" pull_request feat-x main synchronize false)"
check "trunk push main"          "candidate true true DSV,HMG true PRD false true" "$(route "$trunk" push main "" "" "")"
check "trunk push feature"       "none false false - false - false true"          "$(route "$trunk" push feat-x "" "" "")"
check "trunk PR merged"          "none false false - false - false true"          "$(route "$trunk" pull_request feat-x main closed true)"

# ---------- render-deploy-matrix.sh ----------
m=$("$s/render-deploy-matrix.sh" "$root/.github/configs/deploy-config.yml" "DSV, HMG,PRD")
check "matriz: ordem dos ambientes" "DSV HMG PRD" "$(jq -r '[.include[].env] | join(" ")' <<<"$m")"
check "matriz: driver por ambiente" "kubernetes kubernetes gitops-pr" "$(jq -r '[.include[].driver] | join(" ")' <<<"$m")"
check "matriz: override do artefato" "1 2 2 512" "$(jq -r '[.include[].config.replicas] + [.include[2].config.cpu] | join(" ")' <<<"$m")"
check "matriz: grupo de contas" "NPRD NPRD PRD" "$(jq -r '[.include[].account] | join(" ")' <<<"$m")"
check "matriz: settings herdam defaults" "environments" "$(jq -r '.include[2].settings.gitops.branch' <<<"$m")"
check "matriz: sem artifacts nos settings" "null" "$(jq -c '.include[2].settings.artifacts' <<<"$m")"
check "matriz vazia" '{"include":[]}' "$("$s/render-deploy-matrix.sh" "$root/.github/configs/deploy-config.yml" "")"

# ---------- render-manifest.sh ----------
man=$(APP=web-api ENV_NAME=HMG VERSION=1.5.0-12 IMAGE='ghcr.io/o/web-api@sha256:abc' \
      CONFIG='{"containerPort":8080,"replicas":2,"cpu":256,"memory":512}' "$s/render-manifest.sh")
check "manifesto: imagem por digest" "ghcr.io/o/web-api@sha256:abc" "$(yq 'select(.kind=="Deployment") | .spec.template.spec.containers[0].image' <<<"$man")"
check "manifesto: namespace do ambiente" "hmg hmg" "$(yq '.metadata.namespace' <<<"$man" | grep -v '^---' | tr '\n' ' ' | sed 's/ $//')"
check "manifesto: replicas" "2" "$(yq 'select(.kind=="Deployment") | .spec.replicas' <<<"$man")"

echo
echo "testes: $pass ok, $fail falharam"
[ "$fail" -eq 0 ]
