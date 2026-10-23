#!/usr/bin/env bash
# Politica de promocao: cada ambiente so aceita versoes do seu estagio.
#
#   ambientes de release   (flow.environments.release)   -> X.Y.Z com tag publicada
#   ambientes de candidata (flow.environments.candidate) -> X.Y.Z-N com tag (RC) ou X.Y.Z
#   ambientes de snapshot  (flow.environments.snapshot)  -> qualquer versao da esteira
#   ambiente fora do fluxo (ex.: TST so por redeploy)     -> RC ou release, nunca snapshot
#
# Vale para o pipeline e para o redeploy manual, e roda ANTES da aprovacao:
# ninguem e chamado a aprovar um deploy que ja nasceu fora da politica.
# A prova de "ja foi publicada" e a tag git imutavel (ruleset de tags).
#
# uso: check-deploy-policy.sh <ENV1,ENV2,...> <versao>
# env: PIPELINE (pipeline.yml em JSON); com GITHUB_REPOSITORY + gh, consulta as tags pela API
set -euo pipefail

envs=${1:?ambientes}
version=${2:?versao}
: "${PIPELINE:?}"

stage_of() {
  jq -r --arg e "$1" '
    .flow.environments as $f
    | if (($f.release // []) | index($e)) then "release"
      elif (($f.candidate // []) | index($e)) then "candidate"
      elif (($f.snapshot // []) | index($e)) then "snapshot"
      else "outside" end' <<<"$PIPELINE"
}
tag_exists() {
  if [ -n "${GITHUB_REPOSITORY:-}" ] && command -v gh >/dev/null; then
    gh api "repos/$GITHUB_REPOSITORY/git/ref/tags/$1" --silent 2>/dev/null
  else
    git rev-parse -q --verify "refs/tags/$1" >/dev/null
  fi
}

if   [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then kind=release
elif [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+$ ]]; then kind=candidate
elif [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-SNAPSHOT$ ]]; then kind=snapshot
else echo "::error::Versao $version fora do formato da esteira (X.Y.Z, X.Y.Z-N ou X.Y.Z-N-SNAPSHOT)."; exit 1
fi

status=0
for env in ${envs//,/ }; do
  stage=$(stage_of "$env")
  allowed=true
  case "$stage:$kind" in
    release:release) ;;
    release:*) allowed=false ;;
    candidate:snapshot|outside:snapshot) allowed=false ;;
  esac
  if [ "$allowed" = false ]; then
    echo "::error::$env e ambiente de $stage e nao aceita versao $kind ($version). Promova pela esteira: snapshot -> candidata -> release."
    status=1; continue
  fi
  if [ "$kind" != snapshot ] && ! tag_exists "$version"; then
    echo "::error::$version nao foi publicada (sem tag): so versoes que passaram pela esteira entram em $env."
    status=1; continue
  fi
  echo "politica ok: $version ($kind) em $env ($stage)"
done
exit "$status"
