#!/usr/bin/env bash
# Driver gitops-pr: grava os manifestos renderizados do ambiente na branch de
# estado (lida pelo Argo CD/Flux). O pipeline nao toca no cluster.
#
# Todos os artefatos gitops-pr do ambiente entram num UNICO commit/PR: o que se
# revisa e aprova e "a versao X neste ambiente", nao cada peca separada.
#
#   mode=pr     abre PR para a branch de estado; o merge E o deploy (revisao humana)
#   mode=commit commita direto na branch de estado (so ambientes nao produtivos)
#
# Deve rodar dentro de um clone do repositorio de estado.
# uso: deploy-gitops.sh <deploy|diff|destroy>
# env: ENV_NAME VERSION IMAGE ARTIFACTS(JSON [{artifact, config}]) STATE_BRANCH MODE
#      STATE_PATH TARGET_REPO GH_TOKEN [CONFIG_DIR] [SECRET_STORE]
set -euo pipefail

cmd=${1:-deploy}
: "${ENV_NAME:?}" "${ARTIFACTS:?}" "${STATE_BRANCH:?}" "${MODE:?}" "${TARGET_REPO:?}"
render="$(cd "$(dirname "$0")" && pwd)/render-manifest.sh"
env_lc=$(tr '[:upper:]' '[:lower:]' <<<"$ENV_NAME")
dir=${STATE_PATH:-envs/$env_lc}
names=$(jq -r '[.[].artifact] | join(", ")' <<<"$ARTIFACTS")

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

# branch de estado: nasce orfa, sem o codigo da aplicacao
if git ls-remote --exit-code --heads origin "$STATE_BRANCH" >/dev/null; then
  git fetch --quiet origin "$STATE_BRANCH"
  git switch --quiet -C "$STATE_BRANCH" "origin/$STATE_BRANCH"
else
  git switch --quiet --orphan "$STATE_BRANCH"
  git rm -rq --cached . 2>/dev/null || true
  git clean -fdxq
  # shellcheck disable=SC2016 # crases literais no markdown
  printf '# Estado dos ambientes\n\nGerado pela esteira. Cada `envs/<ambiente>/` e lido pelo agente GitOps.\n' > README.md
  git add README.md
  git commit --quiet -m "chore(gitops): inicia branch de estado"
  git push --quiet origin "$STATE_BRANCH"
fi

mkdir -p "$dir"
while IFS= read -r item; do
  APP=$(jq -r '.artifact' <<<"$item")
  CONFIG=$(jq -c '.config' <<<"$item")
  export APP CONFIG
  file="$dir/$APP.yaml"
  case "$cmd" in
    diff)
      tmp=$(mktemp); "$render" > "$tmp"
      if [ -f "$file" ]; then diff -u "$file" "$tmp" || true; else echo "novo: $file"; cat "$tmp"; fi ;;
    destroy)
      if [ -f "$file" ]; then git rm --quiet "$file"; fi ;;
    deploy)
      : "${VERSION:?}" "${IMAGE:?}"
      "$render" > "$file"
      git add "$file" ;;
    *) echo "comando invalido: $cmd" >&2; exit 1 ;;
  esac
done < <(jq -c '.[]' <<<"$ARTIFACTS")
[ "$cmd" = diff ] && exit 0

if [ "$cmd" = destroy ]; then message="chore(gitops): remove $names de $ENV_NAME"
else message="deploy($env_lc): $VERSION ($names)"; fi

if git diff --cached --quiet; then
  echo "Nada muda em $dir: $ENV_NAME ja esta neste estado."
  exit 0
fi

if [ "$MODE" = commit ]; then
  git commit --quiet -m "$message"
  git push --quiet origin "$STATE_BRANCH"
  echo "Estado de $ENV_NAME atualizado direto em $STATE_BRANCH."
  exit 0
fi

work="deploy/$env_lc/${VERSION:-remove}"
git switch --quiet -c "$work"
git commit --quiet -m "$message" -m "Run $GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"
# branch so do pipeline: re-run do mesmo deploy sobrescreve a tentativa anterior
git push --quiet --force origin "$work"
url=$(gh pr list -R "$TARGET_REPO" --head "$work" --base "$STATE_BRANCH" --json url --jq '.[0].url')
if [ -z "$url" ]; then
  url=$(gh pr create -R "$TARGET_REPO" --base "$STATE_BRANCH" --head "$work" --title "$message" \
    --body "Mergear este PR **e** o deploy em $ENV_NAME ($names): o agente GitOps aplica o novo estado no cluster.")
fi
echo "PR de deploy: $url"
echo "### Deploy $ENV_NAME por GitOps: $url" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
