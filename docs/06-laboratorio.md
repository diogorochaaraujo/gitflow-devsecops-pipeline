# 06 · Laboratório ponta a ponta

Do repositório vazio a uma release em PRD, passando por todos os gates. Tempo
estimado: 40 minutos, quase todo esperando runner.

## Pré-requisitos

- conta no GitHub e `gh` autenticado nela (`gh auth status`);
- repositório **público**. Em conta pessoal gratuita, revisor de Environment e
  rulesets só funcionam em repositório público. O bootstrap avisa e segue se não
  der.

## 1. Criar e preparar o repositório

```bash
gh repo create <voce>/gitflow-devsecops-pipeline --public --source . --push
scripts/bootstrap-repo.sh <voce>/gitflow-devsecops-pipeline
```

O primeiro push na `main` não dispara nada (o snapshot ignora a `main`). O
bootstrap cria a `dsv`, os labels, os Environments (PRD com você como revisor),
as regras da `main` e das tags, e libera o `GITHUB_TOKEN` para abrir PR.

## 2. Uma tarefa: snapshot sem deploy

```bash
git switch -c TASK-1 origin/dsv
# mude a resposta de "/" em app/app.py
git commit -am "feat(api): campo novo na raiz" -m "Refs: TASK-1"
git push -u origin TASK-1
```

**Observe** em *Actions → Snapshot*: Prepare, Security, Build, Container e Report
rodam. *Environment Deploy* aparece como **skipped**, porque `TASK-1` não está em
`SnapshotBranches`. No resumo do run, a versão: `0.1.0-<n>-SNAPSHOT`.

## 3. Integração: deploy em DSV

```bash
gh pr create --base dsv --fill && gh pr merge --merge
```

O merge é um push na `dsv`. **Observe:** o snapshot agora tem *Environment
Deploy → DSV*: cluster kind sobe, rollout, smoke test (`Smoke test ok: web-api
0.1.0-<n>-SNAPSHOT em DSV`) e o relatório do ZAP como artefato. Em *Settings →
Environments → DSV* aparece o histórico de deploy.

## 4. Release: PR `dsv → main`

```bash
gh pr create --base main --head dsv --title "release: primeira versao" --body "primeira release"
```

**Observe a primeira recusa:** sem label, *Commits Validations* falha com
`O PR precisa de exatamente um label...`. *Error Analysis* repete a mensagem no
resumo.

```bash
gh pr edit --add-label Release-Minor
```

O label dispara o Start Release de novo (`types: labeled`). Agora sim: gates,
*Release Validation* verde, *Create Release Stamp* cria a tag `0.1.0-<n>`, e
*Deploy NPROD* entrega em HMG.

```bash
git fetch --tags && git tag -l   # a RC aparece
```

## 5. Merge e produção

```bash
gh pr merge --merge     # merge commit, nunca squash
```

**Observe** o Finish Release:

1. *Release Validation* acha a RC no commit;
2. *Promote Artifact* cria `0.1.0` apontando para o **mesmo digest** da RC.
   Confira com `docker buildx imagetools inspect ghcr.io/<voce>/web-api:0.1.0` e
   `...:0.1.0-<n>`;
3. *Deploy → PRD* fica **aguardando aprovação**. Aprove em *Review deployments*;
4. *Back-merge* abre o PR `main → dsv`. Mergeie (merge commit).

Em *Releases* aparece a `0.1.0` com as notas geradas.

## 6. Quebre de propósito

Cada experimento mostra um gate. Faça numa branch de tarefa e abra PR para a `dsv`.

| Experimento | Como | O que deve acontecer |
|---|---|---|
| segredo no código | `echo "TOKEN=ghp_$(LC_ALL=C tr -dc A-Za-z0-9 </dev/urandom \| head -c 36)" > app/config.txt` (token falso, aleatório; valores com `EXAMPLE` são ignorados pela ferramenta) | *Secrets* falha no snapshot da branch. Remover o arquivo num commit novo **não** resolve, porque o scan lê o histórico inteiro: é preciso reescrever a branch, e com um segredo real, revogá-lo |
| dependência vulnerável | crie `app/requirements.txt` com `django==2.2.0` | *SCA* falha listando as CVEs críticas |
| exceção com prazo | adicione as CVEs no `.trivyignore.yaml` com `expired_at` no futuro, depois no passado | passa, depois volta a falhar |
| branch atrás da main | mergeie algo direto na `main` (via PR de hotfix) e atualize o PR de release sem trazer a `main` | *Commits Validations*: `N commit(s) atras de main` |
| PR sem Start Release | tente mergear o PR de release com o check vermelho | o ruleset bloqueia o botão de merge |
| app que não sobe | faça `route("/health")` em `app/app.py` devolver `503` | readiness nunca passa, o rollout não estabiliza e o job mostra pods e logs |
| rollback manual | *Actions → Redeploy*: `deploy`, versão anterior, PRD | aprovação, e a versão antiga volta |

## 7. Separar a plataforma (opcional)

Siga [01 · Arquitetura → Separando as camadas](01-arquitetura.md#separando-as-camadas)
para ver o desenho real: um repositório de plataforma com tag `v1` e esta app
consumindo de lá.

## 8. Driver ECS (opcional, conta AWS própria)

1. Crie (via IaC ou console) cluster, ALB, um serviço `web-api-dsv` e uma task
   definition inicial com container `web-api`;
2. crie um provedor OIDC para `token.actions.githubusercontent.com` e um papel
   que confie no repositório (`repo:<voce>/<repo>:environment:DSV`);
3. em *Settings → Variables*: `AWS_REGION`, `AWS_ROLE_ARN_NPRD`
   (e `AWS_ROLE_ARN_PRD` se separar contas);
4. troque `serverType: ecs` no `deploy-config.yml`.

O driver não foi exercitado pelo laboratório: veja o cabeçalho de
`scripts/deploy-ecs.sh`.
