#!/usr/bin/env bash
# Driver de deploy em AWS ECS (Fargate): nova revisao da task definition com a
# imagem entregue e troca rolante do servico do ambiente.
#
# Pressupoe a infraestrutura ja criada pela esteira de IaC (cluster, ALB,
# servico `<app>-<env>` e task definition inicial). Aqui so se troca a imagem
# -- o mesmo corte entre "IaC da infra" e "deploy da aplicacao" do modelo de
# referencia (docs/01-arquitetura.md#iac-e-deploy-sao-esteiras-diferentes).
#
# ATENCAO: driver de referencia, nao exercitado pelo laboratorio. Para puxar do
# GHCR o ECS precisa de `repositoryCredentials`; o mais simples e espelhar a
# imagem para um ECR da conta.
#
# uso: deploy-ecs.sh <deploy|diff|destroy>
# env: APP, ENV_NAME, VERSION, IMAGE, CONFIG (JSON do artefato no ambiente)
set -euo pipefail

cmd=${1:-deploy}
: "${APP:?}" "${ENV_NAME:?}" "${CONFIG:?}"

env_lc=$(tr '[:upper:]' '[:lower:]' <<<"$ENV_NAME")
cluster=$(jq -r '.cluster // empty' <<<"$CONFIG")
service=$(jq -r --arg d "$APP-$env_lc" '.service // $d' <<<"$CONFIG")
: "${cluster:?config do artefato sem 'cluster'}"

current=$(aws ecs describe-services --cluster "$cluster" --services "$service" \
  --query 'services[0].taskDefinition' --output text)

case "$cmd" in
  destroy)
    aws ecs update-service --cluster "$cluster" --service "$service" --desired-count 0 >/dev/null
    echo "$service escalado para zero em $cluster"
    ;;
  diff)
    aws ecs describe-task-definition --task-definition "$current" \
      --query "taskDefinition.containerDefinitions[?name=='$APP'].image" --output text \
      | sed "s|^|atual:   |"
    echo "entrega: ${IMAGE:-<sem versao>}"
    ;;
  deploy)
    : "${VERSION:?}" "${IMAGE:?}"
    aws ecs describe-task-definition --task-definition "$current" --query taskDefinition \
      | jq --arg img "$IMAGE" --arg name "$APP" --arg v "$VERSION" '
          .containerDefinitions |= map(
            if .name == $name then
              .image = $img
              | .environment = ((.environment // []) | map(select(.name != "APP_VERSION")) + [{name: "APP_VERSION", value: $v}])
            else . end)
          | del(.taskDefinitionArn, .revision, .status, .requiresAttributes,
                .compatibilities, .registeredAt, .registeredBy)' > taskdef.json
    new=$(aws ecs register-task-definition --cli-input-json file://taskdef.json \
      --query taskDefinition.taskDefinitionArn --output text)
    aws ecs update-service --cluster "$cluster" --service "$service" --task-definition "$new" >/dev/null
    echo "Aguardando $service estabilizar com $new ..."
    aws ecs wait services-stable --cluster "$cluster" --services "$service"
    echo "Deploy ok: $APP $VERSION em $ENV_NAME"
    ;;
  *)
    echo "comando invalido: $cmd" >&2; exit 1 ;;
esac
