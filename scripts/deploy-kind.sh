#!/usr/bin/env bash
# Driver de deploy do laboratorio: cluster kind efemero no proprio runner.
# Um namespace por ambiente; aplica o manifesto, espera o rollout e confere,
# pelo /health, que a versao que responde e a versao entregue.
#
# uso: deploy-kind.sh <deploy|diff|destroy>
# env: APP, ENV_NAME, VERSION, IMAGE, CONFIG (JSON do artefato no ambiente)
set -euo pipefail

cmd=${1:-deploy}
: "${APP:?}" "${ENV_NAME:?}" "${CONFIG:?}"

NS=$(tr '[:upper:]' '[:lower:]' <<<"$ENV_NAME")
PORT=$(jq -r '.containerPort // 8080' <<<"$CONFIG")
HEALTH=$(jq -r '.healthPath // "/health"' <<<"$CONFIG")
REPLICAS=$(jq -r '.replicas // 1' <<<"$CONFIG")
CPU=$(jq -r '.cpu // 256' <<<"$CONFIG")
MEMORY=$(jq -r '.memory // 512' <<<"$CONFIG")
export NS APP ENV_NAME PORT HEALTH REPLICAS CPU MEMORY VERSION="${VERSION:-}" IMAGE="${IMAGE:-}"

render() { envsubst < "$(dirname "$0")/../templates/kind/app.yaml"; }

case "$cmd" in
  destroy)
    kubectl delete namespace "$NS" --ignore-not-found
    ;;
  diff)
    kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    render | kubectl diff -f - || [ $? -eq 1 ]
    ;;
  deploy)
    : "${VERSION:?}" "${IMAGE:?}"
    kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -
    render | kubectl apply -f -
    if ! kubectl -n "$NS" rollout status "deployment/$APP" --timeout=180s; then
      echo "::error::Rollout de $APP em $ENV_NAME nao estabilizou."
      kubectl -n "$NS" get pods -o wide || true
      kubectl -n "$NS" logs "deployment/$APP" --tail=50 || true
      exit 1
    fi

    kubectl -n "$NS" port-forward "svc/$APP" 18080:"$PORT" >/dev/null 2>&1 &
    pf=$!
    trap 'kill $pf 2>/dev/null || true' EXIT
    for _ in $(seq 1 20); do curl -fsS "http://127.0.0.1:18080$HEALTH" -o health.json 2>/dev/null && break; sleep 1; done
    running=$(jq -r '.version' health.json)
    if [ "$running" != "$VERSION" ]; then
      echo "::error::Smoke test: $ENV_NAME responde $running, esperado $VERSION."
      exit 1
    fi
    echo "Smoke test ok: $APP $running em $ENV_NAME"
    ;;
  *)
    echo "comando invalido: $cmd" >&2; exit 1 ;;
esac
