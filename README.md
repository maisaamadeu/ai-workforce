# AI Workforce

Aplicativo desktop para orquestrar trabalho de IA com autorização de consumo antes de qualquer chamada a provedor.

O Flutter é o 3.50.0, pinado pelo FVM. O núcleo em `packages/workforce_core` decide modo, política, pausa e plano. A interface em `app/` fala com esse núcleo no mesmo processo. Nenhum CLI recebe prompt nesta versão. Disponibilidade que ainda não foi consultada aparece como não verificada, e consumo não medido não vira zero.

## Executar

```bash
fvm install
fvm flutter run -d linux
```

No macOS ou no Windows, troque `linux` por `macos` ou `windows`. O banco SQLite fica no diretório de dados do sistema. `AI_WORKFORCE_HOME` aponta outro diretório.

## Verificação

```bash
(cd packages/workforce_core && fvm dart test)
(cd packages/workforce_system_macos && fvm dart test)
(cd packages/workforce_system_windows && fvm dart test)
(cd app && fvm flutter test)
```

A árvore `apps/` e `packages/authorization` é a fundação anterior em Node e React. Os testes dela continuam com `npm test`.
