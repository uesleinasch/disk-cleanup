# Restauração, backup automático e conflitos

Complementa [2026-11-09-backup-design.md](2026-11-09-backup-design.md), que deixava de fora a restauração pelo app e o backup automático.

## Decisões

| Tema | Decisão |
| --- | --- |
| Backup automático | Ao conectar o disco e/ou por intervalo (1 h, 6 h, 12 h, 1 dia, 7 dias). Só com o app aberto: sem daemon, sem systemd. |
| Direção | Mão única, computador para o disco. |
| Segredos no automático | Ficam de fora; pedem senha pelo pinentry e isso só acontece quando a pessoa pede. |
| Conflitos no backup | Tudo que não tem conflito é copiado; os conflitos ficam em **Pendentes**. |
| Conflitos na restauração | Dry-run antes de copiar; regra em lote mais ajuste arquivo a arquivo. |
| Escopo da restauração | Pastas (inteiras ou itens escolhidos), perfis de navegador, pacote de segredos, tudo de uma vez. |

## Manifesto

`<destino>/<pasta do backup>/.disk-cleanup-manifest.json`, gravado no passo Guia (tmp + rename): data, hostname, home, nome da pasta, origens (`path`, `name`) e navegadores (`id`, `label`, `profilePath`). A restauração usa o manifesto para saber o destino original. Backups antigos sem manifesto casam as pastas pelo basename com as origens configuradas; o que não casar pede um destino. Ao restaurar em outro usuário, caminhos dentro do home antigo são trocados para o home atual.

## Restauração

1. **Escolher**: o backup do disco configurado ou outro aberto pela pasta; os itens; o destino (lugar original ou `~/Restaurado-AAAA-MM-DD/`).
2. **Analisar**: por item, `rsync -aHn -8 --itemize-changes --out-format='%i %n' [-r --from0 --files-from]`. `>f+++++++++` é arquivo novo; `>f` com `s`, `t` ou `c` é conflito, a menos que o conteúdo seja igual byte a byte. O rsync escapa caracteres de controle como `\#ooo`; o parser desfaz. Segredos são abertos antes (`gpg -d | tar x`) numa pasta 0700 em `$XDG_RUNTIME_DIR`, apagada no fim.
3. **Revisar**: regra em lote (mais recente, manter o atual, usar o backup, manter os dois) e ajuste por arquivo.
4. **Restaurar**: `rsync -aH --from0 --files-from=<novos + substituir> --backup --backup-dir=$XDG_DATA_HOME/disk-cleanup/substituidos/<data-hora>/<item>`; "manter os dois" copia a versão do backup como `nome (backup AAAA-MM-DD).ext` com `cp -p --no-clobber`. Segredos terminam com `chmod -R go-rwx` em `.ssh` e `.gnupg`.

Regras: nunca `--delete`; destino só dentro do home ou dos diretórios mapeados, conferido depois de resolver symlinks (`isRestorableTarget`); perfil de navegador aberto bloqueia só aquele item; senha errada e janela fechada são reconhecidas pelas linhas `[GNUPG:]` (`--status-fd 2`), não pelo texto traduzido.

## Backup automático

- `MountWatcher`: `findmnt --poll -n -r -o ACTION,TARGET` contínuo, reiniciado com espera crescente; sem findmnt, fica só o relógio.
- `AutoSyncScheduler`: a cada minuto e 10 s depois de cada montagem, resolve o disco configurado. Dispara se o disco **acabou de aparecer** (com "Ao conectar" ligado; ao abrir o app com ele já conectado, não) ou se o intervalo venceu desde o último backup e desde a última tentativa.
- Só começa com o backup parado, sem restauração em curso (`BackupLock`) e sem problemas na configuração. Roda `start(auto: true)`: sem Segredos, navegador aberto é pulado. Terminando sem falha, a tela volta ao normal sozinha; com falha, o resumo fica na tela.
- Avisos por SnackBar ("Fazendo o backup automático em …", "concluído", "falhou" com ação "Ver o que houve") e indicador no item Backup do menu lateral.

## Conflitos no backup (Pendentes)

Antes de copiar as pastas, um dry-run na direção do backup (`backupRsyncArgs` + `-8 --itemize-changes`) acha:

- **Mais novo no disco**: arquivo alterado cujo mtime no disco é maior que o local e o conteúdo difere.
- **Seria apagado** (só com Espelhar): linhas `*deleting`; o que está dentro de uma pasta que também seria apagada é agrupado na pasta.

Cada caminho vira a regra `- /<pasta>/<rel>` (com `rsyncLiteral`), acrescentada às regras do backup. Sem `--delete-excluded`, isso impede tanto a cópia quanto a remoção. A lista é regravada a cada backup em `$XDG_DATA_HOME/disk-cleanup/pendentes.json`, por disco.

| Tipo | Ações |
| --- | --- |
| Mais novo no disco | Enviar o do computador (a versão do disco vai para `<backup>/.substituidos/`), Trazer o do disco (a local vai para `substituidos` no computador), Manter os dois (`nome (do disco AAAA-MM-DD).ext` no computador) |
| Seria apagado | Apagar do disco (`SafeDeleter` com raiz na pasta do backup), Manter no disco (lembrado em `keepOnDisk` e não volta a perguntar) |

A Visão geral mostra um banner quando há pendentes; o menu lateral mostra a contagem.
