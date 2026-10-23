#!/usr/bin/env bash
# Monta a matriz de deploy: um item por (ambiente, artefato).
#   ordem    = ambientes na ordem pedida; dentro do ambiente, artifacts.<a>.order (padrao 100)
#   settings = defaults * envs.<ENV> (sem artifacts, reviewers, waitTimer)
#   config   = artifacts.<a> * envs.<ENV>.artifacts.<a>
#   driver   = config.driver (artefato, com override no ambiente) > envs.<ENV>.driver > defaults.driver
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
      | ($c.defaults * ($e | del(.artifacts, .reviewers, .waitTimer))) as $settings
      | [ ($c.artifacts | keys[]) as $artifact
          | ($c.artifacts[$artifact] * (($e.artifacts // {})[$artifact] // {})) as $config
          | {
              env: $env,
              artifact: $artifact,
              account: (($c.accounts // {})[$env] // $env),
              driver: ($config.driver // $settings.driver),
              settings: $settings,
              config: $config
            } ]
      | sort_by(.config.order // 100, .artifact)
      | to_entries[]
      | .value + {order: ($i * 1000 + .key)} ]
  | {include: .}'
