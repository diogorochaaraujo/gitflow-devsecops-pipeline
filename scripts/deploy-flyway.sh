#!/usr/bin/env bash
# Driver flyway: aplica as migracoes do artefato no banco do ambiente.
#
#   DB_URL presente          -> migrate no banco do ambiente (credencial do Environment)
#   DB_URL ausente + efemero -> sobe um Postgres descartavel e valida que as
#                               migracoes aplicam do zero (laboratorio, PR)
#   destroy                  -> recusado: este driver nunca apaga banco
#
# Senha so por variavel de ambiente (nunca em argumento: apareceria no `ps`).
#
# uso: deploy-flyway.sh <deploy|diff|destroy>
# env: APP ENV_NAME CONFIG SETTINGS MIGRATIONS_DIR FLYWAY_IMAGE POSTGRES_IMAGE
#      [DB_URL DB_USER DB_PASSWORD]
set -euo pipefail

cmd=${1:-deploy}
: "${APP:?}" "${ENV_NAME:?}" "${CONFIG:?}" "${SETTINGS:?}" "${MIGRATIONS_DIR:?}" "${FLYWAY_IMAGE:?}"

schema=$(jq -r '.flyway.schema // "public"' <<<"$CONFIG")
ephemeral=$(jq -r '.flyway.ephemeral // false' <<<"$SETTINGS")
[ -d "$MIGRATIONS_DIR" ] || { echo "::error::$APP: pasta de migracoes $MIGRATIONS_DIR nao existe."; exit 1; }

if [ "$cmd" = destroy ]; then
  echo "::error::destroy nao se aplica a banco: remover dados e operacao manual, fora da esteira."
  exit 1
fi

network=host
cleanup() { :; }
if [ -z "${DB_URL:-}" ]; then
  if [ "$ephemeral" != true ]; then
    echo "::error::Environment $ENV_NAME sem DB_URL/DB_USER/DB_PASSWORD e flyway.ephemeral desligado."
    exit 1
  fi
  : "${POSTGRES_IMAGE:?}"
  network="flyway-$GITHUB_RUN_ID-$APP"
  docker network create "$network" >/dev/null
  DB_USER=app
  DB_PASSWORD=$(openssl rand -hex 16)
  DB_URL="jdbc:postgresql://db:5432/app"
  export POSTGRES_PASSWORD=$DB_PASSWORD
  docker run -d --rm --name "db-$network" --network "$network" --network-alias db \
    -e POSTGRES_USER=app -e POSTGRES_DB=app -e POSTGRES_PASSWORD "$POSTGRES_IMAGE" >/dev/null
  cleanup() { docker rm -f "db-$network" >/dev/null 2>&1 || true; docker network rm "$network" >/dev/null 2>&1 || true; }
  trap cleanup EXIT
  for _ in $(seq 1 30); do docker exec "db-$network" pg_isready -U app -d app >/dev/null 2>&1 && break; sleep 1; done
  echo "Banco efemero de validacao pronto ($ENV_NAME, nada e persistido)."
fi

export FLYWAY_URL=$DB_URL FLYWAY_USER=${DB_USER:-} FLYWAY_PASSWORD=${DB_PASSWORD:-}
flyway() {
  docker run --rm --network "$network" -v "$MIGRATIONS_DIR:/flyway/sql:ro" \
    -e FLYWAY_URL -e FLYWAY_USER -e FLYWAY_PASSWORD "$FLYWAY_IMAGE" \
    -schemas="$schema" -locations=filesystem:/flyway/sql -validateMigrationNaming=true "$@"
}

case "$cmd" in
  diff)
    flyway info ;;
  deploy)
    flyway migrate
    flyway info
    echo "Migracoes ok: $APP em $ENV_NAME (schema $schema)" ;;
  *)
    echo "comando invalido: $cmd" >&2; exit 1 ;;
esac
