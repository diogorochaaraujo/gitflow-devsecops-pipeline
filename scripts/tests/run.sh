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
check "gitflow PR->main editado" "candidate true true HMG false - false true"     "$(route "$gitflow" pull_request dsv main edited false)"
check "gitflow PR->main merged"  "promote false false - true PRD true true"       "$(route "$gitflow" pull_request dsv main closed true)"
check "gitflow PR->main fechado" "none false false - false - false true"          "$(route "$gitflow" pull_request dsv main closed false)"
check "gitflow PR->dsv"          "none false false - false - false true"          "$(route "$gitflow" pull_request TASK-1 dsv opened false)"
check "trunk PR->main"           "verify true false - false - false true"         "$(route "$trunk" pull_request feat-x main synchronize false)"
check "trunk push main"          "candidate true true DSV,HMG true PRD false true" "$(route "$trunk" push main "" "" "")"
check "trunk push feature"       "none false false - false - false true"          "$(route "$trunk" push feat-x "" "" "")"
check "trunk PR merged"          "none false false - false - false true"          "$(route "$trunk" pull_request feat-x main closed true)"

# ---------- render-deploy-matrix.sh ----------
m=$("$s/render-deploy-matrix.sh" "$root/.github/configs/deploy-config.yml" "DSV, HMG,PRD")
check "matriz: banco antes da app em cada ambiente" "DSV:web-api-db DSV:web-api HMG:web-api-db HMG:web-api PRD:web-api-db PRD:web-api" \
  "$(jq -r '[.include[] | "\(.env):\(.artifact)"] | join(" ")' <<<"$m")"
check "matriz: driver do artefato vence o do ambiente" "flyway kubernetes flyway kubernetes flyway gitops-pr" "$(jq -r '[.include[].driver] | join(" ")' <<<"$m")"
check "matriz: ordem crescente" "0 1 1000 1001 2000 2001" "$(jq -r '[.include[].order] | join(" ")' <<<"$m")"
check "matriz: override do artefato no ambiente" "1 2 2 512" "$(jq -r '[.include[] | select(.artifact=="web-api") | .config.replicas] + [.include[5].config.cpu] | join(" ")' <<<"$m")"
check "matriz: grupo de contas" "NPRD PRD" "$(jq -r '[.include[1].account, .include[5].account] | join(" ")' <<<"$m")"
check "matriz: settings herdam defaults" "environments true" "$(jq -r '.include[5].settings | "\(.gitops.branch) \(.flyway.ephemeral)"' <<<"$m")"
check "matriz: reviewers/artifacts fora dos settings" "null null" "$(jq -r '.include[5].settings | "\(.reviewers) \(.artifacts)"' <<<"$m")"
check "matriz vazia" '{"include":[]}' "$("$s/render-deploy-matrix.sh" "$root/.github/configs/deploy-config.yml" "")"

be=$("$s/render-deploy-matrix.sh" --by-env "$root/.github/configs/deploy-config.yml" "DSV,PRD")
check "por ambiente: um item por ambiente" "DSV PRD" "$(jq -r '[.include[].env] | join(" ")' <<<"$be")"
check "por ambiente: artefatos em ordem" "web-api-db web-api" "$(jq -r '[.include[0].artifacts[].artifact] | join(" ")' <<<"$be")"
check "por ambiente: drivers do ambiente" "flyway,gitops-pr" "$(jq -r '.include[1].drivers | join(",")' <<<"$be")"

# ---------- deploy-gitops.sh: varios artefatos, um commit ----------
gx=$(mktemp -d); git init -q --bare "$gx/state.git"; git clone -q "$gx/state.git" "$gx/w" 2>/dev/null
( cd "$gx/w" && git config user.email t@t && git config user.name t
  ENV_NAME=HMG VERSION=2.0.0 IMAGE='img@sha256:abc' STATE_BRANCH=environments MODE=commit TARGET_REPO=o/r GITHUB_RUN_ID=1 \
  ARTIFACTS='[{"artifact":"api","config":{"containerPort":8080}},{"artifact":"worker","config":{"args":["run"]}}]' \
  "$s/deploy-gitops.sh" deploy >/dev/null 2>&1 )
check "gitops: os dois manifestos no estado" "api.yaml worker.yaml" "$(git --git-dir="$gx/state.git" ls-tree --name-only environments envs/hmg/ | xargs -n1 basename | tr '\n' ' ' | sed 's/ $//')"
check "gitops: um unico commit de deploy" "deploy(hmg): 2.0.0 (api, worker)" "$(git --git-dir="$gx/state.git" log -1 --format=%s environments)"
check "gitops: digest no manifesto" "img@sha256:abc" "$(git --git-dir="$gx/state.git" show environments:envs/hmg/api.yaml | yq 'select(.kind=="Deployment") | .spec.template.spec.containers[0].image')"
rm -rf "$gx"

# ---------- render-manifest.sh ----------
mf() { "$s/render-manifest.sh"; }
man=$(APP=web-api ENV_NAME=HMG VERSION=1.5.0-12 IMAGE='ghcr.io/o/web-api@sha256:abc' CONFIG_DIR="$root/config" \
      CONFIG='{"containerPort":8080,"replicas":2,"cpu":256,"memory":512}' mf)
check "manifesto: imagem por digest" "ghcr.io/o/web-api@sha256:abc" "$(yq 'select(.kind=="Deployment") | .spec.template.spec.containers[0].image' <<<"$man")"
check "manifesto: documentos" "ConfigMap Deployment Service" "$(yq '.kind' <<<"$man" | grep -v '^---' | tr '\n' ' ' | sed 's/ $//')"
check "manifesto: configmap do ambiente" "ola do ambiente HMG" "$(yq 'select(.kind=="ConfigMap") | .data.GREETING' <<<"$man")"
check "manifesto: envFrom do configmap" "web-api-config" "$(yq 'select(.kind=="Deployment") | .spec.template.spec.containers[0].envFrom[0].configMapRef.name' <<<"$man")"
check "manifesto: checksum forca rollout" "16" "$(yq 'select(.kind=="Deployment") | .spec.template.metadata.annotations."checksum/config"' <<<"$man" | tr -d '\n' | wc -c | tr -d ' ')"
wk=$(APP=web-worker ENV_NAME=DSV VERSION=1 IMAGE=img CONFIG='{"args":["python","worker.py"]}' mf)
check "worker: sem Service" "Deployment" "$(yq '.kind' <<<"$wk" | grep -v '^---' | tr '\n' ' ' | sed 's/ $//')"
check "worker: args e sem probe" '["python","worker.py"] null' "$(yq -o=json -I=0 'select(.kind=="Deployment") | [.spec.template.spec.containers[0].args, .spec.template.spec.containers[0].readinessProbe]' <<<"$wk" | jq -r '"\(.[0]|tojson) \(.[1])"')"
sec=$(APP=web-api ENV_NAME=PRD VERSION=1 IMAGE=img CONFIG='{"containerPort":8080,"secrets":["BANCO"]}' SECRET_STORE=cofre mf)
check "secrets: ExternalSecret com chave por convencao" "web-api/prd/BANCO cofre" "$(yq 'select(.kind=="ExternalSecret") | .spec.data[0].remoteRef.key + " " + .spec.secretStoreRef.name' <<<"$sec")"
APP=web-api ENV_NAME=PRD VERSION=1 IMAGE=img CONFIG='{"secrets":["BANCO"]}' mf >/dev/null 2>&1; check "secrets sem secretStore recusado" "1" "$?"
mkdir -p "$work/cfg/x"; echo "API_TOKEN=abc" > "$work/cfg/x/dsv.env"
APP=x ENV_NAME=DSV VERSION=1 IMAGE=img CONFIG='{}' CONFIG_DIR="$work/cfg" mf >/dev/null 2>&1; check "segredo em arquivo de config recusado" "1" "$?"

# ---------- check-migrations.sh ----------
mig=$(mktemp -d); ( cd "$mig" && git init -q -b main && git config user.email t@t && git config user.name t
  mkdir -p db/migrations .github/configs
  printf 'defaults: {driver: kubernetes}\nartifacts:\n  app-db: {driver: flyway, flyway: {locations: db/migrations}}\n' > .github/configs/deploy-config.yml
  echo "CREATE TABLE a (id int);" > db/migrations/V1__a.sql; git add -A; git commit -qm v1; git tag 1.0.0 )
( cd "$mig" && echo "CREATE TABLE b (id int);" > db/migrations/V2__b.sql && git add -A && git commit -qm v2 )
( cd "$mig" && "$s/check-migrations.sh" >/dev/null 2>&1 ); check "migracao nova aceita" "0" "$?"
( cd "$mig" && echo "-- editada" >> db/migrations/V1__a.sql && git commit -qam edita )
( cd "$mig" && "$s/check-migrations.sh" >/dev/null 2>&1 ); check "migracao publicada alterada recusada" "1" "$?"
rm -rf "$mig"

# ---------- validate-pr.sh: chamado ----------
pr=$(mktemp -d); ( cd "$pr" && git init -q --bare remote.git && git init -q -b main w && cd w && git config user.email t@t && git config user.name t \
  && git commit -q --allow-empty -m i && git remote add origin ../remote.git && git push -q origin main )
vp() { ( cd "$pr/w" && BASE_REF=main HEAD_SHA=$(git rev-parse HEAD) LABELS='["Release-Minor"]' CHANGE_REF='[A-Z][A-Z0-9]+-[0-9]+' \
  PR_TITLE=$1 PR_BODY=$2 HEAD_REF=$3 "$s/validate-pr.sh" >/dev/null 2>&1 ); echo $?; }
check "chamado no titulo" "0" "$(vp "release LAB-12" "" dsv)"
check "chamado na branch" "0" "$(vp "release" "" "OPS-7-ajuste")"
check "sem chamado recusado" "1" "$(vp "release" "sem referencia" dsv)"
rm -rf "$pr"

# ---------- metadado das composite actions (o actionlint nao valida) ----------
for f in "$root"/.github/actions/*/action.yml; do
  ok=$(yq -e '.name and .runs.using == "composite" and (.runs.steps | length > 0)' "$f" 2>/dev/null || echo erro)
  check "action valida: ${f#"$root"/}" "true" "$ok"
done

# ---------- classify-error.sh ----------
cls() { printf '%s\n' "$1" | "$s/classify-error.sh" | cut -f1; }
check "classifica: action invalida e plataforma" "plataforma" "$(cls 'Failed to load /x/.platform/.github/actions/build-container/action.yml')"
check "classifica: label" "processo" "$(cls 'O PR precisa de exatamente um label Release-Major')"
check "classifica: chamado" "processo" "$(cls 'O PR de release precisa citar um chamado no titulo')"
check "classifica: teste python" "build" "$(cls 'FAILED (failures=1)')"
check "classifica: teste node" "build" "$(cls '3 failing')"
check "classifica: migracao" "processo" "$(cls 'Migracao publicada em 1.0.0 foi alterada em db/migrations.')"
check "classifica: desconhecido" "nao classificado" "$(cls 'algo totalmente novo')"

echo
echo "testes: $pass ok, $fail falharam"
[ "$fail" -eq 0 ]
