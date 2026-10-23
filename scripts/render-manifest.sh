#!/usr/bin/env bash
# Renderiza o manifesto Kubernetes de um artefato num ambiente (stdout).
# Fonte unica para os drivers kubernetes (aplica) e gitops-pr (grava no repo de estado).
#
# env: APP ENV_NAME VERSION IMAGE CONFIG(JSON do artefato) [NAMESPACE]
set -euo pipefail

: "${APP:?}" "${ENV_NAME:?}" "${VERSION:?}" "${IMAGE:?}" "${CONFIG:?}"

NS=${NAMESPACE:-$(tr '[:upper:]' '[:lower:]' <<<"$ENV_NAME")}
PORT=$(jq -r '.containerPort // 8080' <<<"$CONFIG")
HEALTH=$(jq -r '.healthPath // "/health"' <<<"$CONFIG")
REPLICAS=$(jq -r '.replicas // 1' <<<"$CONFIG")
CPU=$(jq -r '.cpu // 256' <<<"$CONFIG")
MEMORY=$(jq -r '.memory // 512' <<<"$CONFIG")
export NS APP ENV_NAME VERSION IMAGE PORT HEALTH REPLICAS CPU MEMORY

# so as variaveis do template: um ${...} estranho no manifesto fica intacto
# shellcheck disable=SC2016 # a lista de variaveis do envsubst e literal
envsubst '${NS} ${APP} ${ENV_NAME} ${VERSION} ${IMAGE} ${PORT} ${HEALTH} ${REPLICAS} ${CPU} ${MEMORY}' \
  < "$(dirname "$0")/../templates/kubernetes/app.yaml"
