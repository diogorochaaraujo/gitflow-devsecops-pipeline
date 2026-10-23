#!/usr/bin/env bash
# Monta a matriz de deploy: um item por (ambiente, artefato).
#   ordem    = ambientes na ordem pedida; dentro do ambiente, artifacts.<a>.order (padrao 100)
#   settings = defaults * envs.<ENV> (sem artifacts, reviewers, waitTimer)
#   config   = artifacts.<a> * envs.<ENV>.artifacts.<a>
#   driver   = config.driver (artefato, com override no ambiente) > envs.<ENV>.driver > defaults.driver
#
# uso: render-deploy-matrix.sh [--by-env] <deploy-config.yml> <ENV1,ENV2,...>
# saida (padrao): {"include":[{"order":..,"env":..,"artifact":..,"account":..,"driver":..,"settings":{..},"config":{..}}]}
# saida (--by-env): um item por ambiente, com os artefatos em ordem -- e a forma
#   que o deploy usa: UM job por ambiente = UMA aprovacao por ambiente
#   {"include":[{"env":..,"account":..,"settings":{..},"drivers":[..],"artifacts":[{"artifact":..,"driver":..,"config":{..}}]}]}
set -euo pipefail

by_env=false
[ "${1:-}" = --by-env ] && { by_env=true; shift; }
file=${1:?deploy-config.yml}
envs=${2:-}

yq -o=json '.' "$file" | jq -c --arg envs "$envs" --argjson byenv "$by_env" '
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
  | if $byenv then
      [ group_by(.order / 1000 | floor)[]
        | {env: .[0].env, account: .[0].account, settings: .[0].settings,
           drivers: (map(.driver) | unique),
           artifacts: map({artifact, driver, config})} ]
    else . end
  | {include: .}'
