# 06 · Laboratório ponta a ponta

Do repositório vazio a uma release em PRD por GitOps, passando por todos os
gates. Uns 40 minutos, quase todos esperando runner.

## Pré-requisitos

- `gh` autenticado na sua conta (`gh auth status`);
- repositório **público**: numa conta gratuita, revisor de Environment, rulesets
  e attestations só funcionam em repositório público.

## 1. Criar e preparar

```bash
gh repo create <voce>/gitflow-devsecops-pipeline --public --source . --push
scripts/bootstrap-repo.sh <voce>/gitflow-devsecops-pipeline
```

O bootstrap cria a `dsv`, os labels, os Environments (com os revisores de
`envs.<ENV>.reviewers` do `deploy-config.yml`),
as regras da `main` (PR, merge commit, `Pipeline / Gate` verde, branch em dia) e
das tags (imutáveis). A criação da `dsv` já dispara o primeiro **snapshot com
deploy em DSV**.

## 2. Tarefa: snapshot sem deploy

```bash
git switch -c TASK-1 origin/dsv
# mude a resposta de "/" em app/app.py
git commit -am "feat(api): campo novo na raiz" -m "Refs: TASK-1"
git push -u origin TASK-1
```

**Observe** em *Actions → Pipeline*:

- *Resolve* mostra `Etapa: snapshot`;
- Security e Build rodam;
- no Build, o log do step *Container* termina com a attestation registrada;
- os jobs de deploy aparecem como **skipped**, porque `TASK-1` não é a branch
  de integração.

## 3. Integração: DSV

```bash
gh pr create --base dsv --fill && gh pr merge --merge
```

O push na `dsv` faz snapshot **com deploy em DSV**, em ordem: primeiro
`web-api-db` (Flyway num Postgres descartável: `Migracoes ok`), depois `web-api`,
com *Verify Artifact*
(`Proveniência verificada: ...@sha256:...`), cluster kind, rollout, smoke test
(`Smoke test ok: web-api 0.x.0-<n>-SNAPSHOT em DSV`) e DAST.

## 4. Release: PR `dsv → main`

```bash
gh pr create --base main --head dsv --title "release: primeira versao" --body "primeira release"
```

**Primeira recusa, em segundos:** *Resolve* → *Commits Validations*: `O PR
precisa de exatamente um label...`. Com o label e sem chamado, a segunda: `O PR
de release precisa citar um chamado...`. Basta editar o título (`... (LAB-1)`):
`edited` também reavalia. Em *Report → Error Analysis* aparece a
classe **processo** e o que fazer.

```bash
gh pr edit --add-label Release-Minor --title "release: primeira versao (LAB-1)"
```

O label redispara (`types: labeled`). Agora: gates, *Gate* verde, *Stamp*
(`0.1.0-<n>`), *Deploy candidate* em HMG (de novo: banco primeiro, depois a API).

## 5. Merge e produção por GitOps

```bash
gh pr merge --merge
```

**Observe:**

1. *Promote* cria `0.1.0` com o **mesmo digest** da RC (`Mesmo digest:
   sha256:...`), a tag git e a GitHub Release;
2. *Deploy release → PRD* espera **aprovação**. Aprove em *Review deployments*;
   a aprovação vale para os dois artefatos do ambiente;
3. `web-api-db` aplica as migrações (no lab, validação efêmera); depois o driver
   `gitops-pr` verifica a attestation de `web-api` e abre um PR para a branch
   `environments` com `envs/prd/web-api.yaml` apontando para
   `web-api@sha256:...`. **O merge desse PR é o deploy de produção**;
4. *Back-merge* abre o PR `main → dsv`. Mergeie com merge commit.

## 6. Quebre de propósito

Cada experimento mostra um controle. Faça numa branch de tarefa. A última coluna
diz como cada controle foi verificado neste repositório: **GitHub** (executado na
esteira real), **teste** (coberto por `scripts/tests/run.sh`, que roda no Platform
CI) ou **local** (reproduzido em Docker durante o desenvolvimento).

| Experimento | Como | O que deve acontecer | Verificado |
|---|---|---|---|
| config com erro de digitação | troque `container:` por `contaner:` no `pipeline.yml` | *Resolve* falha em segundos: `Additional properties are not allowed ('contaner' ...)` | local |
| sem teste | apague `test:` do bloco `python` | *Build* falha: `Nenhum teste: defina build.python.test...` | — |
| segredo no código | `echo "TOKEN=ghp_$(LC_ALL=C tr -dc A-Za-z0-9 </dev/urandom \| head -c 36)" > app/config.txt` (token falso; valores com `EXAMPLE` são ignorados pelo scanner) | *Secrets* falha. Remover num commit novo **não** resolve, porque o scan lê o histórico: é preciso reescrever a branch e, com segredo real, revogá-lo | local |
| dependência vulnerável | `app/requirements.txt` com `django==2.2.0` | *SCA* falha com CVEs críticas | — |
| exceção com prazo | as CVEs no `.trivyignore.yaml` com `expired_at` futuro, depois passado | passa, depois volta a falhar | — |
| imagem fora da esteira | `docker build` local, `docker push ghcr.io/<voce>/web-api:9.9.9`, e *Redeploy* `9.9.9` em DSV | *Verify Artifact* recusa: sem attestation do `stage-build.yml` | GitHub (com imagem de uma versão antiga da esteira, sem attestation) |
| branch atrás da main | hotfix direto na `main` e o PR de release sem trazer a `main` | *Commits Validations*: `N commit(s) atras de main` | local |
| app que não sobe | faça `route("/health")` devolver `503` | rollout não estabiliza; o job mostra pods e logs | — |
| migração publicada editada | depois da primeira release, edite `db/migrations/V1__*.sql` | *Resolve*: `Migracao publicada em X.Y.Z foi alterada`; a correção é uma `V2__*.sql` | teste |
| segredo no arquivo de configuração | `DB_PASSWORD=x` em `config/web-api/dsv.env` | o deploy recusa: chave com cara de segredo vai em `secrets` | teste |
| segredo sem cofre | `secrets: [BANCO]` em `web-api` | o deploy recusa: o ambiente não tem `kubernetes.secretStore` | teste |
| rollback manual | *Actions → Redeploy*: `deploy`, versão anterior, DSV | entrega a versão antiga **com a configuração e as migrações dela** (commit gravado na imagem), com verificação | GitHub |
| aprovação esquecida | deixe o PRD esperando e rode *Actions → Housekeeping* | issue *Deploys aguardando aprovacao* com a data de expiração | GitHub (sem pendência: a rotina roda e fecha a issue) |

## 7. Trunk-based (opcional)

Num repositório novo, copie `examples/node-trunk-gitops/` (ou troque `flow.model:
trunk` e `versioning: conventional` neste). PRs para `main` rodam *verify*; cada
merge na `main` gera RC pelos commits, entrega em `candidate` em ordem, promove e
pede aprovação para PRD.

> O roteamento do trunk é coberto por teste (`scripts/tests/run.sh`), mas o fluxo
> ainda não rodou de ponta a ponta num repositório real.

## 8. Separar a plataforma

[01 · Arquitetura → Separando as camadas](01-arquitetura.md#separando-as-camadas).
É o passo que dá às attestations o nível SLSA L3 e permite proteger a esteira
do time da aplicação.
