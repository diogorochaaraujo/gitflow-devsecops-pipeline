# 04 · Config as code e GitOps

A aplicação descreve a si mesma em arquivos versionados. A plataforma os valida
(`schemas/`) e os lê a cada execução. Nenhuma configuração de esteira mora numa
tela.

## `pipeline.yml`

```yaml
app:
  name: web-api                 # nome da imagem, do Deployment, do serviço

flow:
  model: gitflow                # gitflow | trunk
  integrationBranch: dsv        # só gitflow
  versioning: label             # label | conventional (trunk exige conventional)
  environments:
    snapshot: [DSV]             # gitflow: push na integração
    candidate: [HMG]            # PR de release (gitflow) ou merge na main (trunk), em ordem
    release: [PRD]              # depois da promoção

build:
  stack: python                 # node | python | java | container
  python:                       # bloco da stack escolhida (obrigatório)
    version: "3.12"
    workingDirectory: app
    install: ""                 # vazio = requirements*.txt / pyproject.toml
    lint: ruff check .
    test: python -m unittest discover -v
  container:                    # sempre: a imagem é o artefato entregue
    context: app
    dockerfile: app/Dockerfile

security:
  skipOnSnapshot: []            # sast | sca | iac | container (nunca vale na candidata)
```

| Stack | Bloco | Padrões |
|---|---|---|
| `node` | `version`, `workingDirectory`, `packageManager` (`npm`/`pnpm`/`yarn`), `lint`, `test`, `build` | scripts `lint`/`test`/`build` do `package.json` |
| `python` | `version`, `workingDirectory`, `install`, `lint`, `test` | `pytest` |
| `java` | `version`, `distribution`, `tool` (`maven`/`gradle`), `workingDirectory`, `test` | `mvn verify` / `gradle build` (wrapper se existir) |
| `container` | `test` (opcional) | só a imagem; testes dentro do Dockerfile |

**Teste é obrigatório.** Nos módulos `node` e `python`, se não houver teste para
executar, o build falha (`Nenhum teste: defina ...`). No `java`, o padrão é
`verify`, que roda os testes. Uma esteira que aceita `-DskipTests` mede
cobertura de nada.

## `.github/configs/deploy-config.yml`

```yaml
defaults:                       # vale para todo ambiente
  driver: kubernetes            # kubernetes | gitops-pr | ecs
  kubernetes:
    cluster: kind               # kind | aks | kubeconfig
  gitops:
    repository: ""              # vazio = este repositório
    branch: environments
    mode: pr                    # pr | commit

accounts:                       # ambiente -> grupo de credenciais
  DSV: NPRD
  PRD: PRD

artifacts:                      # base de cada artefato
  web-api:
    containerPort: 8080
    healthPath: /health
    replicas: 1
    cpu: 256                    # millicores
    memory: 512                 # MiB

envs:
  PRD:
    driver: gitops-pr           # um ambiente pode trocar de driver
    artifacts:
      web-api:
        replicas: 2
```

Valor efetivo: **`defaults` ← `envs.<ENV>`** para driver e acesso, e
**`artifacts.<a>` ← `envs.<ENV>.artifacts.<a>`** para o dimensionamento. Para ver
sem rodar nada:

```bash
scripts/render-deploy-matrix.sh .github/configs/deploy-config.yml DSV,HMG,PRD | jq
```

| Driver | Configuração | Credencial |
|---|---|---|
| `kubernetes` + `kind` | — | nenhuma (efêmero) |
| `kubernetes` + `aks` | `resourceGroup`, `clusterName`, `namespace` | vars `AZURE_TENANT_ID`, `AZURE_CLIENT_ID_<GRUPO>`, `AZURE_SUBSCRIPTION_ID_<GRUPO>` (federada) |
| `kubernetes` + `kubeconfig` | `namespace` | segredo `KUBECONFIG` **do Environment** |
| `gitops-pr` | `repository`, `branch`, `mode`, `path` | `github.token` (mesmo repo) ou segredo `GITOPS_TOKEN` do Environment |
| `ecs` | `ecs.cluster` | vars `AWS_REGION`, `AWS_ROLE_ARN_<GRUPO>` (OIDC) |

Segredos ficam **no Environment**, nunca no repositório: o job de deploy só os
recebe depois da aprovação daquele ambiente.

## GitOps

Pelos [princípios do OpenGitOps](https://opengitops.dev/), o estado desejado
precisa ser **declarativo**, **versionado e imutável**, **puxado** por um agente e
**reconciliado continuamente**.

| Driver | 1 declarativo | 2 versionado | 3 puxado | 4 reconciliado |
|---|---|---|---|---|
| `kubernetes` / `ecs` (push) | ✅ | ✅ (tag + digest) | ❌ | ❌ (drift só aparece no próximo deploy) |
| `gitops-pr` | ✅ | ✅ (o estado guarda o **digest**) | ✅ agente no cluster | ✅ |

Com `gitops-pr`, o pipeline **não tem credencial do cluster**:

```mermaid
flowchart LR
  subgraph CI["esteira"]
    B["build + gates<br/>+ attestation"] --> V["verify-artifact"]
    V --> PR["PR: envs/prd/web-api.yaml<br/>image: web-api@sha256:…"]
  end
  PR --> ST[("branch/repo de estado")]
  AG["Argo CD / Flux<br/>no cluster"] -->|pull + reconcilia| ST
  AG --> K[(cluster)]
  POL["admission policy<br/>verifica attestation"] -.-> K
```

- a branch de estado (`environments` por padrão) nasce órfã, só com
  `envs/<env>/<app>.yaml`, e é o que o Argo CD/Flux observa;
- `mode: pr`: o merge do PR, revisado por alguém do cliente, **é** o deploy, e o
  histórico do git é o histórico de produção;
- `mode: commit`: para ambientes não produtivos, sem revisão;
- no cluster, uma política de admissão (Sigstore policy-controller ou Kyverno
  `verifyImages`) pode exigir a mesma attestation. Assim, nem quem tem acesso
  ao repositório de estado consegue colocar uma imagem arbitrária.

No laboratório, PRD usa `gitops-pr` na própria branch `environments` deste
repositório: o PR é aberto e mergeado, mas não há agente aplicando, porque o
cluster `kind` morre com o runner. Para ver a reconciliação de verdade, aponte
um Argo CD para `envs/prd` dessa branch.
