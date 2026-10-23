# Confiança OIDC presa ao workflow da plataforma

O padrão ingênuo confia no **repositório** (`repo:org/app:*`). Assim, qualquer
workflow do repositório assume o papel de deploy, inclusive um que o fornecedor
escreva. Aqui a confiança fica presa a **qual workflow** pede o token: o
reusable de deploy da plataforma, numa versão publicada.

## 1. Incluir `job_workflow_ref` no `sub` do token

```bash
# por organização (vale para todos os repositórios) ou por repositório
gh api -X PUT orgs/<org>/actions/oidc/customization/sub \
  -f 'include_claim_keys[]=repo' -f 'include_claim_keys[]=context' -f 'include_claim_keys[]=job_workflow_ref'
```

Com isso, o `sub` de um job de deploy em PRD vira:

```
repo:<org>/<app>:environment:PRD:job_workflow_ref:<org>/pipeline-platform/.github/workflows/stage-deploy.yml@refs/tags/v2.1.0
```

## 2. Confiar só nesse formato

| Nuvem | Arquivo | Como casa |
|---|---|---|
| AWS (IAM role) | [`aws-trust-policy.json`](aws-trust-policy.json) | `StringLike` no `sub`, com curinga só no repositório |
| Azure (Entra ID, *federated credential*) | [`azure-federated-credential.json`](azure-federated-credential.json) | `subject` exato, um por ambiente; a versão da plataforma entra no `subject` |
| Kubernetes / Vault / outros | mesmo `sub` | regra de *bound claims* do emissor |

Resultado: um papel de PRD só é assumido por **job do ambiente PRD**, rodando o
**deploy da plataforma**, numa **tag publicada**. Workflow do fornecedor,
branch arbitrária ou versão não publicada da plataforma recebem *AccessDenied*.

Trocar a versão da plataforma exige atualizar a confiança. Isso é proposital:
promover a plataforma vira uma mudança de infraestrutura revisada.
