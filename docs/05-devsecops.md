# 05 · DevSecOps

## Gates por momento

| Análise | Ferramenta aqui | Snapshot | Start Release | Finish Release |
|---|---|---|---|---|
| segredos no histórico | gitleaks | ✅ | ✅ | — |
| SAST | semgrep (`p/default`, severidade ERROR) | ✅ (pulável) | ✅ obrigatório | — |
| SCA (dependências) | trivy fs | ✅ (pulável) | ✅ obrigatório | — |
| IaC (Dockerfile, manifestos) | trivy config | ✅ (pulável) | ✅ obrigatório | — |
| imagem | trivy image | ✅ (pulável) | ✅ obrigatório | — |
| DAST | OWASP ZAP baseline contra o ambiente entregue | DSV | HMG | — |
| qualidade (Sonar) | não incluído | — | — | no modelo de referência, sobre a `main` |

Cada linha de `security-config.yml` tem `enabled` (roda ou não) e `gate`
(quebra ou só registra). Comece com `gate: false` num scanner novo, conheça o
ruído, depois ligue.

## Classificação da aplicação decide o mínimo

No modelo de referência, o conjunto obrigatório não é escolha do time: vem do
**catálogo de aplicações**. Uma app classificada como de escopo prioritário (por
exemplo, exposta à Internet) **precisa** ter SAST, SCA e DAST cadastrados. Se
faltar cadastro em qualquer um, o build para no `Prepare Build`, em ~2 minutos,
com os jobs de build e scan aparecendo como *skipped*.

Esse sintoma é o mais importante de reconhecer: **o código nunca compilou**. Não
adianta mexer em código. O conserto é administrativo (cadastrar a ferramenta,
ou registrar uma exceção).

## Exceções com prazo

Achado aceito não se apaga do scanner: registra-se, **com data para vencer**:

```yaml
# .trivyignore.yaml
vulnerabilities:
  - id: CVE-2026-12345
    paths: ["app/requirements.txt"]
    statement: sem correcao publicada; funcao afetada nao e usada. Dono: @time-da-app
    expired_at: 2026-12-31
```

Vencido o prazo, o achado volta a quebrar o build sozinho, sem que ninguém
precise lembrar. No modelo de referência as exceções ficam num registro central,
consultado em tempo de execução. A vantagem do arquivo versionado é que a
exceção passa por PR e tem autor.

## Achados que o próprio template encontrou nele mesmo

Ao rodar o semgrep sobre a primeira versão destes workflows, dois achados
`ERROR` apareceram. Os dois também existem no modelo de referência:

1. **`secrets: inherit`** nos workflows finos: o reusable recebe *todos* os
   segredos do repositório, inclusive os que não usa. Se o template central for
   comprometido, leva tudo. Aqui nenhum reusable precisa de segredo, porque o
   deploy AWS usa OIDC. Por isso a linha foi removida. Quando precisar, passe só
   o necessário: `secrets: { NOME: ${{ secrets.NOME }} }`.
2. **Interpolação `${{ }}` dentro de `run:`**: o valor vira código shell antes de
   rodar. Um nome de branch ou título de PR malicioso executa comandos no runner.
   Tudo passa por `env:` e é lido como `"$VAR"`.

## Cadeia de suprimentos

- imagem publicada com **SBOM** e **proveniência** (`sbom: true`,
  `provenance: mode=max`);
- produção recebe **o mesmo digest** testado em HMG (promoção por tag, sem
  rebuild);
- tags imutáveis por ruleset;
- deploy AWS por **OIDC**, sem chave de acesso guardada;
- *pendente, de propósito, para o laboratório:* fixar actions e imagens por
  **SHA** em vez de tag (`actions/checkout@<sha> # v4`) e deixar o Dependabot ou
  o Renovate atualizar. Ver [07 · Melhorias](07-melhorias.md).

## Responsabilidade sobre os achados

A ferramenta de scan diz *o quê*, não *quem*. O padrão que funciona: **uma issue
viva por repositório**, com checklist de achados, reescrita a cada scan e fechada
sozinha quando zera, usando o identificador estável do achado (o mesmo entre
scans) como chave. Em DEV, exige-se que tudo esteja **mapeado e priorizado**. Em
HMG e PRD, gate limpo.
