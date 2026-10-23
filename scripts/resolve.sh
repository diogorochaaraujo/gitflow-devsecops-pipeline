#!/usr/bin/env bash
# Decide o que esta execucao faz, a partir do evento e do modelo de fluxo.
#
#   stage      snapshot | verify | candidate | promote | none
#   build      constroi e analisa o commit
#   stamp      cria a tag da release candidate depois dos gates
#   pre-envs   ambientes que recebem o artefato do build (snapshot ou candidata)
#   promote    promove a RC para X.Y.Z (mesmo digest, tag e release)
#   post-envs  ambientes que recebem a versao promovida
#   back-merge abre PR da main de volta para a branch de integracao
#   publish    publica imagem (false para bots: token so leitura, sem segredos;
#              o build testa e analisa, mas nao empurra nada)
#
#                     gitflow                              trunk
#   push !main        snapshot (deploy so na integracao)   none (o PR verifica)
#   push main         none (o merge do PR promove)         candidate + promote
#   PR -> main        candidate                            verify
#   PR -> main merged promote + back-merge                 none (o push na main faz)
#
# env: EVENT REF_NAME BASE_REF PR_ACTION PR_MERGED ACTOR PIPELINE(JSON)
set -euo pipefail

: "${EVENT:?}" "${PIPELINE:?}"
cfg() { jq -r "$1" <<<"$PIPELINE"; }
envs() { cfg "(.flow.environments.$1 // []) | join(\",\")"; }

model=$(cfg '.flow.model')
integration=$(cfg '.flow.integrationBranch // ""')
main=main
bot=false
case "${ACTOR:-}" in *"[bot]") bot=true ;; esac

stage=none build=false stamp=false pre="" promote=false post="" backmerge=false

pr_open=false
case "${PR_ACTION:-}" in opened|reopened|synchronize|labeled|unlabeled) pr_open=true ;; esac

case "$model:$EVENT" in
  gitflow:push)
    if [ "$REF_NAME" != "$main" ]; then
      stage=snapshot build=true
      if [ "$REF_NAME" = "$integration" ] && [ "$bot" = false ]; then pre=$(envs snapshot); fi
    fi ;;
  gitflow:pull_request)
    if [ "$BASE_REF" = "$main" ]; then
      if [ "$pr_open" = true ]; then
        stage=candidate build=true stamp=true pre=$(envs candidate)
      elif [ "$PR_ACTION" = closed ] && [ "${PR_MERGED:-false}" = true ]; then
        stage=promote promote=true post=$(envs release) backmerge=true
      fi
    fi ;;
  trunk:push)
    if [ "$REF_NAME" = "$main" ]; then
      stage=candidate build=true stamp=true pre=$(envs candidate) promote=true post=$(envs release)
    fi ;;
  trunk:pull_request)
    if [ "$BASE_REF" = "$main" ] && [ "$pr_open" = true ]; then stage=verify build=true; fi ;;
esac

out() {
  echo "stage=$stage"
  echo "build=$build"
  echo "stamp=$stamp"
  echo "pre-envs=$pre"
  echo "promote=$promote"
  echo "post-envs=$post"
  echo "back-merge=$backmerge"
  echo "publish=$([ "$bot" = true ] && echo false || echo true)"
  echo "integration-branch=$integration"
}
out
if [ -n "${GITHUB_OUTPUT:-}" ]; then out >> "$GITHUB_OUTPUT"; fi
