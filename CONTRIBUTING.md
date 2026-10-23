# Contribuindo

Sugestões, dúvidas e relatos de uso são muito bem-vindos. É assim que o template
melhora.

- **Usou numa organização ou adaptou para outro cenário?** Abra uma *issue*
  contando o contexto (stack, nuvem, número de fornecedores). Esse retorno guia
  as próximas versões.
- **Achou um problema?** Abra uma *issue* com o run que falhou e a etapa do
  [mapa do processo](docs/00-mapa-do-processo.md) em que ele aconteceu.
- **Quer mudar algo?** Abra um PR para a branch `dsv`. O *Platform CI* precisa
  ficar verde: lint, análise de segurança dos workflows, testes dos scripts,
  permissões e schema dos exemplos. O roteiro de extensão está em
  [09 · Extensão](docs/09-extensao.md).

Convenções: [Conventional Commits](https://www.conventionalcommits.org/), com o
identificador da tarefa no rodapé (`Refs: ...`); actions por SHA; imagens por
digest; nada de `${{ }}` dentro de `run:`.

Ao contribuir, você concorda em licenciar a sua contribuição sob os mesmos
termos do projeto: Apache-2.0 para código e CC BY 4.0 para documentação.
