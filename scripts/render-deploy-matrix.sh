#!/usr/bin/env bash
# Monta a matriz de deploy: um item por (ambiente, artefato), em ordem.
#   settings = defaults * envs.<ENV> (sem a chave artifacts)
#   config   = artifacts.<a> * envs.<ENV>.artifacts.<a>
#
# uso: render-deploy-matrix.sh <deploy-config.yml> <ENV1,ENV2,...>
# saida: {"include":[{"order":..,"env":..,"artifact":..,"account":..,"driver":..,"settings":{..},"config":{..}}]}
set -euo pipefail

file=${1:?deploy-config.yml}
envs=${2:-}

yq -o=json '.' "$file" | jq -c --arg envs "$envs" '
  . as $c
  | ($envs | split(",") | map(gsub("\\s"; "")) | map(select(. != ""))) as $list
  | [ range(0; $list | length) as $i
      | $list[$i] as $env
      | (($c.envs // {})[$env] // {}) as $e
      | ($c.defaults * ($e | del(.artifacts))) as $settings
      | ($c.artifacts | keys[]) as $artifact
      | {
          order: $i,
          env: $env,
          artifact: $artifact,
          account: (($c.accounts // {})[$env] // $env),
          driver: $settings.driver,
          settings: $settings,
          config: ($c.artifacts[$artifact] * (($e.artifacts // {})[$artifact] // {}))
        } ]
  | {include: .}'
