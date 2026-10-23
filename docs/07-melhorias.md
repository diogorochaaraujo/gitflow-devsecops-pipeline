# 07 · Lições do modelo de referência

Este template nasceu do estudo de uma esteira corporativa: workflows centralizados, rulesets de organização, scanners
corporativos, deploy por IaC. O desenho de duas camadas funciona. Mas o
histórico de execuções mostrou padrões de falha que se repetem, e cada um virou
uma decisão aqui.

## O que o histórico mostrou e o que o template faz

| # | Observado | Efeito | Aqui |
|---|---|---|---|
| 1 | **Erros de processo e de configuração** (label ausente, branch atrás da main, chave YAML digitada errado, cadastro faltando) eram uma parcela grande das falhas, e só apareciam depois de minutos de pipeline | runner gasto, ciclo lento, ruído que esconde falha real | schema + validação de PR no *Resolve*: falha em segundos, com o campo exato |
| 2 | **Nenhum teste unitário rodava na esteira**: testes pulados por flag no build, scripts de teste inexistentes ignorados, lint não bloqueante; a análise de qualidade de uma stack olhava só o Dockerfile | o quality gate passava sem medir nada | teste obrigatório no módulo da stack; `java` usa `verify` |
| 3 | **Gate de segurança só bloqueava na release**: no snapshot a violação aparecia no log e passava | a release virava a primeira vez que alguém olhava, e a maioria das candidatas era reprovada | mesmos gates no snapshot; o *skip* é exceção explícita |
| 4 | **A imagem candidata era publicada antes dos gates** e o deploy de DSV corria em paralelo ao scan da imagem | candidatas que nunca poderiam ir para produção; imagem não analisada em ambiente | *Stamp* só depois do *Gate*; deploy depende do scan |
| 5 | **Build sem cache**, com dependências instaladas duas vezes (no builder da stack e de novo no `docker build`) | builds longos e caros | cache por stack (`setup-*`) + cache de camadas do buildx |
| 6 | **Deploys de produção expiravam esperando aprovação** (30 dias), sem aviso | entrega perdida em silêncio | *Housekeeping*: issue única com o que está pendente e quando expira |
| 7 | **Deploy em DSV a partir de qualquer branch**, inclusive de bots | uma tarefa sobrescrevia a outra no ambiente compartilhado | só a branch de integração faz deploy; bot só testa |
| 8 | PRs de **bot falhavam** por falta de segredos | ruído constante no histórico | o resolver reconhece bot: testa e analisa, sem publicar |
| 9 | Stack de IaC presa em estado de **rollback incompleto** travava os deploys seguintes até intervenção manual | ambiente parado por dias | rollback automático no driver; GitOps tira o pipeline do caminho |
| 10 | **Workflows centrais em `@main`**, sem versão | uma mudança na plataforma atinge todos os repositórios no mesmo instante | plataforma com tags imutáveis; aplicação pina por SHA com quarentena |
| 11 | **`secrets: inherit`** em todo repositório | o template central recebe todos os segredos de todos os repositórios | nenhum `inherit`; segredos de deploy por Environment; OIDC |
| 12 | A cada execução, o pipeline **reconfigurava o repositório** (times, ambientes, regras) | latência e falhas que nada têm a ver com o código | governança aplicada uma vez, por script idempotente, no nível da organização |
| 13 | A **análise de erro com IA** era útil em erro determinístico, genérica em achado de segurança, e frequentemente terminava em "consulte o time de plataforma" | o diagnóstico não virava ação | classificação determinística por regras versionadas, com "o que fazer" por classe |
| 14 | **Sem prova de origem** da imagem: o deploy confiava na tag | qualquer imagem com a tag certa no registry seria implantada | attestation no build, verificação no deploy, digest em produção |
| 15 | **Diff de IaC desligado** por padrão | mudança de infraestrutura entrava sem pré-visualização | `redeploy diff`; em GitOps o diff é o próprio PR |
| 16 | Rótulo de release **major usado na maioria das releases** | versão perde significado (todo release "quebra compatibilidade") | opção `versioning: conventional`: a versão sai do que mudou |

## Para propor primeiro

Se o objetivo é melhorar uma esteira existente desse tipo, os de maior retorno
por esforço:

1. **#1, validação antecipada.** Um job de segundos antes de tudo elimina a
   maior classe de falhas evitáveis. Não muda nenhum gate.
2. **#3 + #4, gates no lugar certo.** Reordenar dependências e mover a criação
   da tag. Mudança pequena no template central, com efeito em todos os
   repositórios.
3. **#10, versionar a plataforma.** É a pré-condição para mudar qualquer outra
   coisa sem risco para todo mundo ao mesmo tempo.
4. **#6, aprovações pendentes.** Algumas horas de trabalho, e acaba a entrega
   perdida em silêncio.
