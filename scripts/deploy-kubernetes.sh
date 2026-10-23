#!/usr/bin/env bash
# Driver kubernetes: aplica o manifesto no cluster do contexto atual, espera o
# rollout e confere pelo /health que a versao que responde e a entregue.
# Em cluster persistente, rollout que nao estabiliza e desfeito (rollout undo).
# Worker (sem containerPort): so o rollout, sem smoke test.
#
# uso: deploy-kubernetes.sh <deploy|diff|destroy>
# env: APP ENV_NAME VERSION IMAGE CONFIG [NAMESPACE] [EPHEMERAL=true|false] [CONFIG_DIR] [SECRET_STORE]
set -euo pipefail

cmd=${1:-deploy}
: "${APP:?}" "${ENV_NAME:?}" "${CONFIG:?}"
here=$(dirname "$0")
NS=${NAMESPACE:-$(tr '[:upper:]' '[:lower:]' <<<"$ENV_NAME")}
PORT=$(jq -r '.containerPort // 8080' <<<"$CONFIG")
HEALTH=$(jq -r '.healthPath // "/health"' <<<"$CONFIG")
TIMEOUT=$(jq -r '.rolloutTimeout // 180' <<<"$CONFIG")
HAS_PORT=$(jq -r 'has("containerPort")' <<<"$CONFIG")

ensure_ns() { kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null; }

case "$cmd" in
  destroy)
    kubectl -n "$NS" delete deployment,service -l "app.kubernetes.io/name=$APP" --ignore-not-found
    kubectl -n "$NS" delete configmap "$APP-config" --ignore-not-found
    kubectl -n "$NS" delete externalsecret "$APP-secrets" --ignore-not-found 2>/dev/null || true
    ;;
  diff)
    ensure_ns
    "$here/render-manifest.sh" | kubectl diff -f - || [ $? -eq 1 ]
    ;;
  deploy)
    ensure_ns
    "$here/render-manifest.sh" | kubectl apply -f -
    if ! kubectl -n "$NS" rollout status "deployment/$APP" --timeout="${TIMEOUT}s"; then
      echo "::error::Rollout de $APP em $ENV_NAME nao estabilizou."
      kubectl -n "$NS" get pods -o wide || true
      kubectl -n "$NS" logs "deployment/$APP" --tail=50 || true
      if [ "${EPHEMERAL:-false}" != true ]; then
        echo "Desfazendo para a revisao anterior..."
        kubectl -n "$NS" rollout undo "deployment/$APP" || true
        kubectl -n "$NS" rollout status "deployment/$APP" --timeout="${TIMEOUT}s" || true
      fi
      exit 1
    fi

    if [ "$HAS_PORT" = false ]; then
      echo "Rollout ok: $APP (worker, sem smoke test) em $ENV_NAME"
      exit 0
    fi
    kubectl -n "$NS" port-forward "svc/$APP" 18080:"$PORT" >/dev/null 2>&1 &
    pf=$!
    trap 'kill $pf 2>/dev/null || true' EXIT
    running=""
    for _ in $(seq 1 20); do
      running=$(curl -fsS "http://127.0.0.1:18080$HEALTH" 2>/dev/null | jq -r '.version // empty') && [ -n "$running" ] && break
      sleep 1
    done
    if [ "$running" != "$VERSION" ]; then
      echo "::error::Smoke test: $ENV_NAME responde '${running:-nada}', esperado $VERSION."
      exit 1
    fi
    echo "Smoke test ok: $APP $running em $ENV_NAME"
    ;;
  *)
    echo "comando invalido: $cmd" >&2; exit 1 ;;
esac
