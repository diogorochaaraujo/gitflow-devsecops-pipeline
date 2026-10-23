# 07 · Oportunidades de melhoria no modelo de referência

Observado nas execuções do modelo de referência (ordem dos jobs, tempos, saídas)
e comparado com o que este template faz. Ordenado por impacto. Cada item diz o
risco, a proposta e se o template já aplica.

| # | Observado | Risco | Proposta | Template |
|---|---|---|---|---|
| 1 | Workflows centrais referenciados em **`@main`** | uma mudança no template central muda a esteira de todos os repositórios no mesmo instante, sem rollout gradual nem rollback | publicar a plataforma com tags SemVer (`@v3`), mover a major por canal e fixar por SHA nos repositórios críticos | ✅ separação prevê `@v1` |
| 2 | A cada execução, o pipeline **sincroniza times, Environments e rulesets** do repositório (~10 s e várias chamadas de API por run) | latência e cota de API desperdiçadas; um erro de permissão na sincronização quebra build que nada tem a ver com isso | reconciliar configuração de repositório num job agendado (ou via IaC de GitHub), fora do caminho do build | ✅ `bootstrap-repo.sh` idempotente |
| 3 | `secrets: inherit` em todo repositório de aplicação | o template central recebe todos os segredos de todos os repositórios | passar só o necessário; segredo de deploy por Environment; OIDC onde der | ✅ removido |
| 4 | No snapshot, o **deploy em DSV começa junto com o scan de container** (os dois partem do fim do build) | imagem com CVE crítica chega ao DSV antes do resultado do scan | deploy depende do scan da imagem | ✅ `needs: [security, build]` |
| 5 | Start Release **reconstrói** a imagem (~19 min) e o Build cria a **tag da RC antes** dos gates de segurança | RC tagueada que nunca poderia ir para produção; tempo dobrado de build | build único por commit; a RC é só uma tag nova do digest já analisado, criada depois do gate | ✅ tag só após *Release Validation* |
| 6 | O build e o scan de segurança correm em paralelo, mas um **scan reprovado não cancela o build** | 15+ min de runner gastos num resultado já decidido | falha rápida: o job de agregação cancela o run assim que um gate obrigatório reprova | ⚠️ não aplicado (agregação no fim) |
| 7 | Downloads de dependência a cada build, sem cache aparente (centenas de `Downloading ... .pom`) | build lento, pressão no proxy de artefatos | cache de dependências por lockfile no runner ou no buildx (`cache-to: type=gha`) | ✅ cache do buildx |
| 8 | Start Release não reage a **troca de label** (`types: opened, reopened, synchronize`) | o dev coloca o label e precisa de um push vazio para revalidar | incluir `labeled`/`unlabeled` | ✅ |
| 9 | Após o merge, nada traz a `main` de volta para a branch de integração | o próximo PR de release nasce "1 commit atrás" e é recusado; o conserto manual vira rotina (branch `update-main` em todo repo) | PR de back-merge automático no Finish Release | ✅ |
| 10 | Snapshot faz deploy de **qualquer branch** no DSV | duas tarefas em paralelo se sobrescrevem no mesmo ambiente | deploy só da branch de integração; tarefas só build e scan (ou ambientes efêmeros por PR) | ✅ `SnapshotBranches` |
| 11 | **Diff de IaC desligado** por padrão no deploy | mudança de infraestrutura entra sem pré-visualização | diff obrigatório em HMG/PRD, anexado ao run para o aprovador ler antes de aprovar | ⚠️ `redeploy diff` existe; não é etapa obrigatória |
| 12 | **Análise de qualidade (Sonar) só no Finish Release**, depois do merge | o Quality Gate reprova código que já está na `main` | análise no PR de release, com o mesmo gate | ⚠️ Sonar não incluído |
| 13 | Rollback automático só em HMG/PRD; nos demais, falha **desativa o serviço** | DSV fora do ar após qualquer deploy ruim | circuit breaker com rollback em todo ambiente compartilhado | ✅ kind mostra logs e falha; ecs depende do serviço |
| 14 | Serviços de release em HMG/TST nomeados **com a versão** (`<app>-<env>-<versão>-service`), e versões antigas continuam existindo | recursos órfãos acumulando custo; regra de ALB por versão | um serviço por ambiente, versão só na task definition | ✅ `<app>-<env>` |
| 15 | Prioridade de regra do ALB **digitada à mão** por ambiente (301, 302, 303...) | colisão entre ambientes que dividem o ALB; erro só aparece no deploy | derivar a prioridade de (aplicação, ambiente), ou validar unicidade no *Prepare Deploy* | ⚠️ documentado, não implementado |
| 16 | Actions e imagens referenciadas por tag mutável (`@v4`, `:latest`) | supply chain: tag reapontada executa outro código | fixar por SHA + bot de atualização | ⚠️ tags fixas de versão; SHA pendente |
| 17 | Nome do workflow validado **por nome de arquivo** (o Start Release confere se o arquivo se chama `start-release.yml`) | rigidez sem ganho de segurança (o ruleset de push já protege) | validar o `job_workflow_ref` da chamada, não o nome do arquivo | — |

## Por onde começar

Os três de maior retorno por esforço, para propor primeiro:

1. **#4 + #5**: reordenar dependências e mover a criação da tag. Mudança pequena
   no template central, efeito em todos os repositórios: nenhuma imagem sem scan
   em ambiente, nenhuma RC "fantasma".
2. **#9**: back-merge automático. Elimina uma tarefa manual recorrente e o erro
   de pipeline mais comum entre os times.
3. **#1**: versionar a plataforma. É a pré-condição para mudar qualquer outra
   coisa no template sem risco para todo mundo ao mesmo tempo.
