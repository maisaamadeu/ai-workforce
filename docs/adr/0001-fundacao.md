# Fundação local e autorização de consumo

A decisão de interface deste registro foi substituída por [0002-desktop.md](0002-desktop.md). As regras de autorização continuam valendo.

A aplicação roda na máquina do operador. A primeira fundação usava React e uma API Node presa a `127.0.0.1`. O estado fica em SQLite no diretório do usuário. O modo global padrão é o econômico.

O Usage & Authorization Manager decide no servidor se uma tarefa pode usar uma conta. Conta conectada, modelo visível e assinatura ativa não autorizam consumo. A negação em qualquer escopo superior bloqueia. API medida, Fable e modelos de terceiro do Cursor nascem bloqueados.

Uma única conta autorizada cobre análise, planejamento, implementação e revisão. Se a disponibilidade dessa conta acaba, a equipe da tarefa pausa. Não há troca automática para outra cobrança.

Nesta fase os adaptadores ainda não existem. Uma decisão `ready` do manager vira `awaiting-availability`, com o registro explícito de que nenhuma chamada foi feita. Quota, autenticação e catálogo concreto dos CLIs entram na fase 2, pelos binários oficiais `claude`, `codex`, `agent` e `copilot`.
