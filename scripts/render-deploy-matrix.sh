#!/usr/bin/env bash
# Monta a matriz de deploy: um item por (ambiente, artefato), com a config base
# do artefato sobrescrita pelo bloco do ambiente (merge profundo).
#
# uso: render-deploy-matrix.sh <deploy-config.yml> <ENV1,ENV2,...>
# saida (stdout): {"include":[{"env":..,"artifact":..,"serverType":..,"account":..,"config":{..}}]}
set -euo pipefail

file=${1:?deploy-config.yml}
envs=${2:-}

yq -o=json '.' "$file" | jq -c --arg envs "$envs" '
  . as $c
  | [ ($envs | split(",") | map(gsub("\\s"; "")) | map(select(. != "")))[] as $env
      | ($c.artifacts | keys[]) as $artifact
      | {
          env: $env,
          artifact: $artifact,
          serverType: $c.serverType,
          account: ($c.accounts[$env] // $env),
          config: ($c.artifacts[$artifact] * ((($c.envs // {})[$env] // {})[$artifact] // {}))
        } ]
  | {include: .}'
