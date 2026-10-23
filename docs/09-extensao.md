# 09 · Extensão

Toda extensão segue o mesmo caminho: **módulo** (a implementação), **schema**
(o contrato aceita o valor novo), **ponto de encaixe** (o estágio chama o
módulo), **teste** (`scripts/tests/run.sh`) e **exemplo** (`examples/`). O
`platform-ci.yml` cobre lint, segurança dos workflows, testes e schema dos
exemplos. Se ele passa, a extensão está pronta para revisão.

## Uma stack nova (ex.: `dotnet`)

1. `.github/actions/build-dotnet/action.yml`: composite com `setup-dotnet` (por
   SHA), restore com cache, build e **teste obrigatório**;
2. `schemas/pipeline.schema.json`: `dotnet` no `enum` de `build.stack`, o bloco
   `build.dotnet` com `additionalProperties: false`, e o `if/then` que o exige;
3. `stage-build.yml`: um step `Stack (dotnet)` com
   `if: fromJSON(inputs.pipeline).build.stack == 'dotnet'`;
4. `examples/dotnet-.../` com `pipeline.yml` e `deploy-config.yml`.

`uses:` não aceita expressão, por isso cada stack é um step condicional, e não
um `uses: build-${{ stack }}`.

## Um driver de deploy novo (ex.: `helm`)

1. `.github/actions/deploy-helm/action.yml`: recebe `command`, `app`, `env`,
   `version`, `image` (digest), `config` e `settings`, e implementa `deploy`,
   `diff` e `destroy`;
2. `schemas/deploy-config.schema.json`: `helm` no `enum` de `driver` e o bloco
   `helm` em `$defs.settings`;
3. `stage-deploy.yml`: step `Deploy (helm)` com `if: matrix.driver == 'helm'`.
   A credencial vem do grupo (`matrix.account`) ou de segredo do Environment;
4. o driver **recebe o digest já verificado** (`steps.verify.outputs.ref`). Não
   resolva a tag de novo dentro do driver.

## Um fluxo novo (ex.: `release-branches`)

1. `scripts/resolve.sh`: novos casos `release-branches:<evento>` produzindo as
   mesmas saídas (`stage`, `build`, `stamp`, `pre-envs`, `promote`,
   `post-envs`, `back-merge`);
2. `scripts/tests/run.sh`: um `check` por evento relevante. A tabela de
   roteamento é a parte mais fácil de quebrar sem perceber;
3. `schemas/pipeline.schema.json`: o valor no `enum` de `flow.model` e as
   exigências dele (`if/then`).

O orquestrador não muda: ele executa o que o *Resolve* decidir.

## Uma regra de análise de erro

Uma linha em `scripts/error-hints.tsv`:

```
<regex grep -E>	<classe>	<o que fazer>
```

A primeira que casar vence, então regras específicas vão antes das genéricas.

## Uma ferramenta nova na esteira

- action de terceiros: **por SHA**, com a versão em comentário, de uma release
  com pelo menos 14 dias de publicada;
- imagem: **por digest** (`imagem:versão@sha256:...`), na `env:` do workflow;
- sem `${{ }}` em `run:`; `persist-credentials: false`; `timeout-minutes`;
  `permissions` mínimas no job;
- rode `zizmor` e `actionlint` localmente (comandos no README).
