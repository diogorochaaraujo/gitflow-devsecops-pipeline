# 10 · Ciclo de vida da plataforma

A esteira é software que roda em **todos** os repositórios ao mesmo tempo. Uma
mudança errada nela não quebra uma aplicação, quebra todas. Por isso ela precisa
do mesmo rigor que exige das aplicações: versão, gates, ambiente de teste,
promoção e rollback.

## Princípios

1. **A plataforma tem versão.** Tags `vX.Y.Z` imutáveis (ruleset de tags +
   *immutable releases*). Nenhuma aplicação consome `@main`.
2. **A aplicação escolhe quando atualizar.** `ci-cd.yml` aponta para a plataforma
   **por SHA**. O Dependabot propõe a versão nova depois da quarentena, e a
   aplicação adota por PR, passando pelos próprios gates.
3. **Rollback da esteira é voltar o SHA.** Uma versão ruim da plataforma nunca
   prende ninguém.
4. **A esteira se testa antes de ser publicada.** O Platform CI roda lint, análise
   de segurança dos workflows, os testes dos scripts, a checagem de permissões
   dos reusables, o YAML das actions e o schema dos exemplos.
5. **O contrato evolui de forma compatível.** Campo novo tem padrão. Campo
   removido continua aceito, e ignorado, por pelo menos uma major. Um rollback de
   aplicação lê o `deploy-config.yml` antigo com a plataforma atual.

## Neste repositório

Plataforma e aplicação dividem o repositório, mas a aplicação **não** usa o
código da própria branch:

```yaml
# .github/workflows/ci-cd.yml (também redeploy.yml e housekeeping.yml)
uses: diogorochaaraujo/gitflow-devsecops-pipeline/.github/workflows/platform.yml@76e17043... # v1.0.0
```

- **Duas numerações, sem conflito.** `vX.Y.Z` é versão da plataforma;
  `X.Y.Z` e `X.Y.Z-N` são versões da aplicação. O `version.sh` só enxerga as
  segundas.
- **A plataforma sabe qual versão está rodando.** O contexto `github` é do
  chamador, então *Resolve* e *Prepare Deploy* leem `referenced_workflows` do
  próprio run e fazem checkout de scripts e actions **no SHA do pino**. O resumo
  do run e o `audit.json` registram `repositório@sha`.
- **Mudança na plataforma não se testa sozinha no PR.** O PR que altera
  `platform.yml` roda a versão pinada; quem testa a mudança é o *Platform CI*
  (lint, zizmor, testes, permissões, schema). Ela só chega ao pipeline quando
  um PR **move o pino**, e esse PR é o piloto.
- **Atualizar** é um PR que troca o SHA e o comentário nos três workflows. O
  Dependabot abre esse PR sozinho depois da quarentena de 14 dias. Para não
  esperar, troque à mão.
- **Copiou o template?** Duas opções: manter o pino neste repositório, que é a
  separação de verdade (a sua aplicação consome uma plataforma publicada), ou
  publicar a sua plataforma (`git push origin v1.0.0` e trocar o dono no
  `uses:`). O [06 · Laboratório](06-laboratorio.md#1-criar-e-preparar) mostra as duas.

## Como uma mudança na plataforma chega às aplicações

```mermaid
flowchart LR
  B["branch na plataforma"] --> PR["PR"] --> CI["Platform CI<br/>lint · zizmor · testes · schema"]
  CI --> M["merge na main da plataforma"]
  M --> RC["tag de pré-release<br/>v2.3.0-rc.1"]
  RC --> P["repositórios piloto<br/>apontam para a rc"]
  P -->|"fluxo inteiro verde<br/>(E2 → E10)"| T["tag v2.3.0"]
  T --> D["Dependabot abre PR<br/>em cada aplicação"]
  D --> A["aplicação adota<br/>pelo próprio fluxo"]
```

| Passo | O que garante |
|---|---|
| Platform CI no PR | a mudança não quebra lint, segurança dos workflows, scripts nem contrato |
| pré-release em repositórios piloto | a mudança funciona de ponta a ponta numa aplicação real, antes de chegar às outras |
| tag final | a versão é imutável; o que foi testado é o que se publica |
| adoção por PR em cada aplicação | cada time vê o diff da esteira e adota no próprio ritmo; um problema atinge só quem adotou |

**Repositórios piloto** são aplicações reais (ou o próprio laboratório) que
aceitam a pré-release. O critério para publicar a versão final é o fluxo
completo verde no piloto: snapshot, DSV, candidata, HMG, promoção e PRD.

## Comparação com o modelo "fork em outra organização"

Um modelo comum é desenvolver a esteira num **fork do repositório central numa
organização de homologação**, testar com forks das aplicações lá e promover por
PR do fork para a `main` do central, que as aplicações consomem diretamente.

| | Fork em org de homologação, consumo em `@main` | Versão, pré-release e pino por SHA |
|---|---|---|
| isolamento do desenvolvimento | ✅ forte (outra organização) | ✅ branch + Platform CI + piloto |
| teste com aplicação real | ✅ fork da aplicação | ✅ piloto na pré-release |
| chegada às aplicações | **imediata e simultânea**, no merge | gradual: cada aplicação adota por PR |
| rollback | revert na `main` (atinge todos de novo) | voltar o SHA (só quem precisa) |
| saber qual versão da esteira gerou um build | difícil (`@main` muda) | o SHA está no workflow e na attestation |
| custo operacional | duas organizações, forks sincronizados | uma organização; tags e um bot |

Os dois modelos podem conviver. O ganho principal vem de **parar de consumir
`@main`**, e isso vale para qualquer um deles.

## O que fica fora deste repositório, de propósito

### Pipeline de infraestrutura (IaC)

Cluster, rede, banco e cofre têm ciclo próprio:
- `plan` no PR;
- `apply` com aprovação;
- dono diferente do dono da aplicação.

O contrato com esta esteira são as **saídas** da infraestrutura, que alimentam o
`deploy-config.yml`: nome do cluster, namespace, `secretStore`, papéis por grupo
de contas. Misturar os dois pipelines faz um deploy de aplicação recriar
infraestrutura.

### Integração com gestão de mudanças

Hoje, `flow.changeRef` exige que o PR de release **cite** um chamado, e a
checagem acontece **antes do merge** (E5), não depois. O passo seguinte é um
script no mesmo ponto (`scripts/check-change.sh`, extensão) que consulta o sistema
de mudanças e exige o chamado em estado aprovado para a janela. Se a mudança só é
recusada depois do merge, a `main` já tem o código e o problema virou incidente.

### Por que scripts em bash

A lógica de decisão (roteamento, versão, política, matriz, manifesto,
classificação de erro) está em `scripts/*.sh`, não em YAML nem numa action em
JavaScript. É uma troca consciente:

- **a favor**: roda igual no runner e na máquina de quem desenvolve, sem build
  nem dependência; cada regra tem teste (`scripts/tests/run.sh`) e passa por
  shellcheck;
- **contra**: bash fica difícil de manter à medida que cresce, e nem todo time
  de plataforma domina.

Se um script passar de ~150 linhas ou precisar de estrutura de dados de
verdade, o caminho é reescrevê-lo como action (TypeScript ou Go) com a mesma
interface. O teste existente vira o critério de aceite.

### Coleta central de evidências

O `audit.json` de cada execução é a unidade de evidência. Numa organização, um
passo no *Report* o envia para um coletor central (bucket imutável, SIEM, data
lake), e as métricas de entrega (DORA) saem de lá, não da interface.

---

[← 09 · Extensão](09-extensao.md) · [índice](../README.md#comece-por-aqui)
