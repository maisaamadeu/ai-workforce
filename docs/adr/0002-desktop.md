# Aplicativo desktop

O produto passa a ser um aplicativo desktop. A interface Flutter e o Application Core em Dart vivem no mesmo processo. Não há servidor HTTP entre os dois.

O Flutter fica pinado em `.fvmrc` na versão 3.50.0. Comandos de desenvolvimento usam `fvm flutter` e `fvm dart`. O núcleo em `packages/workforce_core` não importa Flutter e guarda o estado em SQLite. A autorização continua negando consumo sem política, mantém API medida bloqueada e pausa a equipe quando a conta autorizada esgota a disponibilidade.

macOS e Windows são os alvos de distribuição. O supervisor POSIX mata o grupo do processo. No Windows o processo entra num Job Object encerrado com `TerminateJobObject`. O Keychain e o Credential Manager ficam nos pacotes de sistema. Nesta versão os adaptadores dos CLIs ainda não executam prompt: uma decisão pronta fica aguardando disponibilidade e nenhuma chamada é feita.

Linux existe como host de desenvolvimento desta máquina. Não é alvo de instalador.
