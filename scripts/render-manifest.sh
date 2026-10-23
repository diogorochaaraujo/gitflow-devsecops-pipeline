#!/usr/bin/env bash
# Renderiza o manifesto Kubernetes de um artefato num ambiente (stdout).
# Fonte unica para os drivers kubernetes (aplica) e gitops-pr (grava no repo de estado).
#
#   base       templates/kubernetes/app.yaml (Deployment + Service)
#   worker     artefato sem containerPort: sem Service, sem probes, sem porta
#   args       artifacts.<a>.args
#   config     <CONFIG_DIR>/<artefato>/<env>.env (CHAVE=VALOR, sem segredo) -> ConfigMap + envFrom,
#              com checksum no pod: mudar a configuracao reinicia os pods
#   secrets    artifacts.<a>.secrets -> ExternalSecret (chave <artefato>/<env>/<NOME> no cofre)
#              + envFrom; exige SECRET_STORE. O pipeline nunca ve o valor.
#
# env: APP ENV_NAME VERSION IMAGE CONFIG(JSON) [NAMESPACE] [CONFIG_DIR] [SECRET_STORE]
set -euo pipefail

: "${APP:?}" "${ENV_NAME:?}" "${VERSION:?}" "${IMAGE:?}" "${CONFIG:?}"

env_lc=$(tr '[:upper:]' '[:lower:]' <<<"$ENV_NAME")
NS=${NAMESPACE:-$env_lc}
PORT=$(jq -r '.containerPort // 8080' <<<"$CONFIG")
HEALTH=$(jq -r '.healthPath // "/health"' <<<"$CONFIG")
REPLICAS=$(jq -r '.replicas // 1' <<<"$CONFIG")
CPU=$(jq -r '.cpu // 256' <<<"$CONFIG")
MEMORY=$(jq -r '.memory // 512' <<<"$CONFIG")
export NS APP ENV_NAME VERSION IMAGE PORT HEALTH REPLICAS CPU MEMORY

# so as variaveis do template: um ${...} estranho no manifesto fica intacto
# shellcheck disable=SC2016 # a lista de variaveis do envsubst e literal
manifest=$(envsubst '${NS} ${APP} ${ENV_NAME} ${VERSION} ${IMAGE} ${PORT} ${HEALTH} ${REPLICAS} ${CPU} ${MEMORY}' \
  < "$(dirname "$0")/../templates/kubernetes/app.yaml")

deploy() { manifest=$(yq "with(select(.kind == \"Deployment\"); $1)" <<<"$manifest"); }
extra=""

if [ "$(jq -r 'has("containerPort")' <<<"$CONFIG")" = false ]; then
  manifest=$(yq 'select(.kind != "Service")' <<<"$manifest")
  deploy 'del(.spec.template.spec.containers[0].ports, .spec.template.spec.containers[0].readinessProbe, .spec.template.spec.containers[0].livenessProbe) | .spec.template.spec.containers[0].env |= map(select(.name != "PORT"))'
fi

if [ "$(jq -r '(.args // []) | length' <<<"$CONFIG")" -gt 0 ]; then
  ARGS=$(jq -c '.args' <<<"$CONFIG") deploy '.spec.template.spec.containers[0].args = (strenv(ARGS) | from_yaml)'
fi

envfile="${CONFIG_DIR:-config}/$APP/$env_lc.env"
if [ -f "$envfile" ]; then
  data=$(grep -vE '^\s*(#|$)' "$envfile" | jq -Rnc '
    [inputs | capture("^(?<k>[A-Za-z_][A-Za-z0-9_]*)=(?<v>.*)$") // error("linha invalida: \(.)")] | map({(.k): .v}) | add // {}')
  suspicious=$(jq -r 'keys[] | select(test("PASS|SECRET|TOKEN|PRIVATE|CREDENTIAL"; "i"))' <<<"$data")
  if [ -n "$suspicious" ]; then
    echo "::error::$envfile tem chave com cara de segredo ($(tr '\n' ' ' <<<"$suspicious")). Segredo vai em artifacts.$APP.secrets, nunca em arquivo de configuracao." >&2
    exit 1
  fi
  checksum=$(sha256sum "$envfile" | cut -c1-16)
  extra+=$(DATA=$data yq -n '
    .apiVersion = "v1" | .kind = "ConfigMap"
    | .metadata.name = strenv(APP) + "-config" | .metadata.namespace = strenv(NS)
    | .data = (strenv(DATA) | from_yaml)')$'\n---\n'
  SUM=$checksum deploy '.spec.template.metadata.annotations."checksum/config" = strenv(SUM)
    | .spec.template.spec.containers[0].envFrom += [{"configMapRef": {"name": strenv(APP) + "-config"}}]'
fi

if [ "$(jq -r '(.secrets // []) | length' <<<"$CONFIG")" -gt 0 ]; then
  if [ -z "${SECRET_STORE:-}" ]; then
    echo "::error::$APP declara secrets, mas $ENV_NAME nao tem kubernetes.secretStore no deploy-config." >&2
    exit 1
  fi
  NAMES=$(jq -c '.secrets' <<<"$CONFIG")
  extra+=$(NAMES=$NAMES ENVLC=$env_lc yq -n '
    .apiVersion = "external-secrets.io/v1" | .kind = "ExternalSecret"
    | .metadata.name = strenv(APP) + "-secrets" | .metadata.namespace = strenv(NS)
    | .spec.refreshInterval = "1h"
    | .spec.secretStoreRef = {"kind": "ClusterSecretStore", "name": strenv(SECRET_STORE)}
    | .spec.target.name = strenv(APP) + "-secrets"
    | .spec.data = [(strenv(NAMES) | from_yaml)[] | {"secretKey": ., "remoteRef": {"key": strenv(APP) + "/" + strenv(ENVLC) + "/" + .}}]')$'\n---\n'
  deploy '.spec.template.spec.containers[0].envFrom += [{"secretRef": {"name": strenv(APP) + "-secrets"}}]'
fi

printf '%s%s\n' "$extra" "$manifest"
