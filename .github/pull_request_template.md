## O que muda

<!-- descreva a mudanca e o motivo -->

## Tipo de release (apenas PR `dsv` -> `main`)

Marque **exatamente um** label. Sem label, o Start Release recusa o PR.

| Label | Quando | Versao `1.4.2` vira |
|---|---|---|
| `Release-Major` | quebra de compatibilidade | `2.0.0` |
| `Release-Minor` | funcionalidade compativel | `1.5.0` |
| `Release-Patch` | correcao compativel | `1.4.3` |

## Checklist

- [ ] A branch esta em dia com a base (sem commits atras)
- [ ] Testes cobrem a mudanca
- [ ] Nenhum segredo, credencial ou dado de ambiente no diff
