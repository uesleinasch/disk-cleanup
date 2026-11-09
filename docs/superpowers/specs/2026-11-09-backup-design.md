# Backup: documento de design

Data: 2026-11-09 · Autor: Ueslei Nascimento · Status: decisões aprovadas em 09/11/2026 (a seção 9 lista o que foi decidido durante a escrita)

## 1. Intenção

Em 08/11/2026, antes de formatar a máquina, o backup foi feito com dois scripts bash: `~/bin/backup-hd.sh` e `~/bin/backup-secrets.sh`. Eles funcionaram e o resultado foi conferido. A origem de ~102 GB virou ~16,25 GB no HD externo (16.252.823.167 bytes, 204 mil arquivos), mais 3,3 GB de perfis de navegador (Brave 1,9 GB de 5,9; Chrome 1,4 GB de 5,4) e um pacote de segredos de ~30 KB. Um `LEIA-ME-RESTAURAR.md` na raiz do HD explicava como voltar tudo.

A feature leva esse fluxo para o app, **de forma genérica**: qualquer pessoa escolhe as pastas, o disco de destino e os navegadores, faz um backup sem dependências e sem caches, guarda as chaves e configurações num pacote criptografado e sai com um guia de restauração no próprio disco.

Os dois scripts são a **implementação de referência**. Onde este documento não disser o contrário, o app reproduz o que eles fazem.

**Sucesso:** conectar o HD, abrir a tela Backup, clicar em "Fazer backup", digitar a senha dos segredos uma vez na janela do sistema e sair. Na volta, o resumo mostra o que foi copiado e o disco tem o backup e o `LEIA-ME-RESTAURAR.md`. Com as mesmas origens, o total copiado é o mesmo dos scripts.

## 2. Objetivos

1. **Pastas:** copiar pastas de origem configuráveis para o destino, sem dependências, caches e builds ignorados pelo git.
2. **Navegadores:** copiar os perfis de Brave, Chrome e Chromium sem cache.
3. **Segredos:** empacotar chaves SSH, configuração do git, GnuPG e keyring num arquivo criptografado com AES256.
4. **Restauração documentada:** gerar o `LEIA-ME-RESTAURAR.md` no destino a partir do que foi de fato copiado.
5. **Controle:** estimativa antes de copiar, progresso, cancelamento e resumo com avisos.
6. **Lembrete:** a Visão geral mostra há quantos dias foi o último backup e alerta depois de um limite.

## 3. Não objetivos

- Backup em nuvem ou em rede como alvo principal.
- Vários destinos ao mesmo tempo.
- Agendamento ou backup automático. O lembrete só aparece com o app aberto.
- Restauração pelo app (tarefa 12, someday). Nesta etapa a restauração é o `LEIA-ME-RESTAURAR.md`.
- Firefox (pode virar tarefa futura).
- Versões ou histórico de backups: existe uma pasta de backup, atualizada a cada execução.
- Editar pela interface a lista de exclusões. Ela é fixa no código nesta versão.

## 4. Antiobjetivos (o que faria a feature fracassar mesmo funcionando)

- **Apagar algo do backup sem o usuário pedir.** O padrão é acumular. Só a opção "Espelhar", desligada por padrão e com aviso, remove do backup o que sumiu da origem.
- **Perder código versionado** por excluir `dist`, `build` ou `bin` só pelo nome (ex.: `vendor/bin` do PHP, `wwwroot/lib/jquery/dist`, `packages/*/bin`).
- **A senha dos segredos passar pelo app**: memória, log, argumento de processo ou arquivo.
- **Segredos em texto puro no destino**, seja por um arquivo temporário do tar, seja porque uma origem contém `~/.ssh`.
- **Corromper um perfil de navegador** copiando com ele aberto, ou fechar o navegador do usuário.
- **Backup "concluído" que não restaura**: destino sem permissões Unix ou erro do rsync escondido no resumo.
- **Travar a interface** durante a cópia.
- **Nomes pessoais no código**: nada de `ueslei`, `JACTO` ou `LOCAL DRIVE` fixo. O app é público (MIT).

## 5. Restrições

- Valem as do spec anterior (`2026-11-06-disk-cleanup-design.md`, seção 5): Flutter Linux, Material 3, interface em pt-BR, comentários só quando inevitáveis, commits sem trailer de coautoria de IA.
- **Nada roda como root.** O backup só lê o que o usuário consegue ler; o que der "Permission denied" vira aviso.
- **Ferramentas externas:** `rsync`, `gpg` (com um pinentry gráfico), `tar`, `git`, `lsblk` e `findmnt`. Se faltar alguma (exit 127, como no Docker), a etapa mostra "não instalado" com o pacote a instalar, e o resto da tela continua usável.
- **Testes com nomes genéricos** (`/home/user/projetos`, `Disco externo`), sem dados pessoais.

## 6. Comportamento

### 6.1 Estrutura no destino

"Destino" é a pasta escolhida: a raiz de um disco montado ou uma subpasta dele.

```
<destino>/
├── LEIA-ME-RESTAURAR.md
├── secrets-AAAA-MM-DD.tar.gz.gpg
└── <pasta do backup>/          padrão: backup
    ├── <origem 1>/              nome da pasta de origem
    ├── <origem 2>/
    └── navegadores/
        ├── brave/
        ├── chrome/
        └── chromium/
```

- A pasta do backup tem **nome fixo e é reaproveitada**: cada execução atualiza a mesma pasta, e o rsync só copia o que mudou. O nome é configurável (padrão `backup`) e não aceita `/`, vazio, `.` ou `..`.
- Cada origem vira uma pasta com o próprio nome, como no script (`rsync origem1 origem2 destino/`, sem barra no fim das origens).
- O pacote de segredos fica na raiz do destino, com a data no nome. Um segundo backup no mesmo dia sobrescreve o pacote do dia; dias diferentes acumulam.
- O `LEIA-ME-RESTAURAR.md` é reescrito a cada execução.

### 6.2 Validação antes de executar

O botão "Fazer backup" só habilita quando tudo abaixo passa. Cada falha aparece junto do item, com o motivo:

- `rsync` instalado; `gpg` e `tar` instalados se os segredos estiverem ligados.
- Destino montado e gravável.
- **Sistema de arquivos com permissões Unix.** Aceitos: `ext2`, `ext3`, `ext4`, `btrfs`, `xfs`, `f2fs`, `zfs`, `nfs` e `nfs4`. Os outros (`vfat`, `exfat`, `ntfs`, `ntfs3`, `fuseblk`, `cifs`…) aparecem desabilitados: "Este disco usa exFAT, que não guarda permissões nem links. Os projetos voltariam quebrados. Formate em ext4 para usar no backup." O tipo vem de `findmnt -J -T <destino>`.
- Ao menos uma origem; todas existem e são pastas.
- **Nomes de origem únicos.** Duas origens com o mesmo nome de pasta (ex.: `~/docs` e `/mnt/dados/docs`) não são aceitas: o app avisa ao adicionar. `navegadores` é nome reservado.
- O destino não fica dentro de uma origem, e nenhuma origem fica dentro do destino.
- Espaço livre no destino maior que "a copiar agora" da estimativa (6.4). Sem estimativa, a validação de espaço acontece na etapa "Preparando".

Avisos que não bloqueiam:

- Destino no mesmo sistema de arquivos de uma origem: "O backup está no mesmo disco das pastas. Ele não protege contra falha do disco."
- Navegador aberto (6.6).

### 6.3 Ordem das etapas

1. **Preparando:** varre as origens atrás de builds ignorados, gera os arquivos de exclusão e roda a estimativa (6.4). Bloqueia se o espaço não couber.
2. **Segredos:** primeiro porque pede a senha, e o usuário ainda está na frente da tela. Se ele cancelar a janela de senha ou o gpg falhar, a etapa vira aviso ("Segredos não salvos") com "Tentar de novo", e o backup segue.
3. **Pastas:** um único rsync com todas as origens.
4. **Navegadores:** um rsync por navegador marcado; o que estiver aberto é pulado com aviso e "Tentar de novo".
5. **Guia:** grava o `LEIA-ME-RESTAURAR.md`, roda `sync` e registra a data do backup (6.10).

O cancelamento interrompe a etapa atual e pula as seguintes. O que já foi copiado fica no destino; a próxima execução continua de onde parou, porque o rsync só copia o que falta.

### 6.4 Exclusões e estimativa (tarefa 4)

**Sempre excluídos** (pastas, em qualquer nível), a lista do script:

```
node_modules .angular .stack-work dist-newstyle .venv venv .terraform .gradle
.dart_tool obj __pycache__ .next .nuxt .cache .pytest_cache .mypy_cache
.turbo .parcel-cache coverage
```

**Excluídos só quando o git ignora:** `dist`, `build`, `bin`, `target` e `out`. O planner procura essas pastas nas origens sem descer em `.git` nem nas pastas sempre excluídas, e pergunta ao git do repositório pai com `git -C <pai> check-ignore -q <nome>/`. Pode agrupar por repositório com `check-ignore --stdin` para não abrir um processo por pasta. Uma pasta fora de qualquer repositório git **é copiada**, como no script. Esse é o lugar em que um comentário no código se justifica: sem ele, alguém "simplifica" para excluir por nome e perde `vendor/bin` versionado.

**Itens de segredo e perfis de navegador dentro de uma origem são excluídos da cópia de pastas.** Se uma origem for o próprio home, `~/.ssh` não pode ir em texto puro para o disco, nem `~/.config/google-chrome` com 5 GB de cache. Eles só vão pelos caminhos próprios (6.6 e 6.7). Isso vale para todo o catálogo, marcado ou não.

**Arquivo de exclusão do rsync**: um só, com as regras separadas por NUL (`--from0`, aceita qualquer nome de pasta), num diretório temporário removido ao fim:

- `- <nome>/` para cada pasta sempre excluída.
- `- /<nome da origem>/<caminho relativo>/` para cada build ignorado, ancorado na raiz da transferência. Se o caminho tiver curinga do rsync (`*`, `?`, `[`), os curingas e a `\` são escapados.
- `- /<nome da origem>/<caminho relativo>` (sem barra no fim, vale para arquivo ou pasta) para itens de segredo e perfis dentro de uma origem.

O `git check-ignore` consulta o índice: uma pasta com qualquer arquivo rastreado não aparece como ignorada, mesmo que o padrão a cubra. Se o git falhar ou não existir, nenhuma pasta de build é excluída.

**Estimativa:** `rsync -aHn --stats` com os mesmos argumentos da cópia real. Do `--stats` saem "Total file size" (tamanho do backup) e "Total transferred file size" (a copiar agora). A tela mostra os dois: "16,3 GB no backup · 1,2 GB a copiar agora". A estimativa roda pelo botão "Calcular" e sempre na etapa Preparando; mudar origens, destino ou "Espelhar" a invalida.

### 6.5 Destino e cópia das pastas (tarefa 5)

**Escolha do destino:**

- `lsblk -J -b -o NAME,LABEL,UUID,FSTYPE,HOTPLUG,SIZE,FSAVAIL,MOUNTPOINT` lista os discos montados. Os de `HOTPLUG=1` aparecem primeiro, como "Discos externos". O campo certo é `HOTPLUG`, não `RM`: um HD USB aparece com `RM=0` e `HOTPLUG=1`. Os loops do snap e o `/boot/efi` ficam de fora.
- "Escolher outra pasta…" abre o seletor nativo (`getDirectoryPath`, como em `directories_page.dart`).
- O destino é salvo como **UUID do sistema de arquivos + caminho relativo ao ponto de montagem** (via `findmnt -J -T`). Assim ele é reconhecido mesmo se o ponto de montagem mudar. Se o disco não estiver conectado, a tela mostra "Conecte o disco <rótulo> para fazer o backup".

**Cópia:**

```
rsync -aH --info=progress2 --no-inc-recursive --stats [--delete] \
  --from0 --exclude-from=<regras> <origem 1> <origem 2> … <destino>/<pasta do backup>/
```

- Roda com `LC_ALL=C` para o formato dos números do progresso e do `--stats` não depender do idioma do sistema.
- `--no-inc-recursive` faz o rsync contar tudo antes, e o percentual do `progress2` passa a ser real. Com ~200 mil arquivos o custo de memória é pequeno.
- Linha de progresso: `  1,234,567  45%   12.34MB/s    0:01:23 (xfr#12, to-chk=100/2000)` vira bytes copiados, percentual, velocidade e tempo restante.
- **Espelhar** acrescenta `--delete` (nunca `--delete-excluded`), com o aviso: "Remove do backup o que você apagou nas pastas de origem." Só age dentro das pastas de origem: uma origem retirada da configuração continua no backup.
- **Códigos de saída:** 0 = concluído; 24 (arquivos sumiram durante a cópia) = concluído com aviso; 23 (alguns arquivos não foram copiados, ex.: sem permissão) = concluído com avisos, listando as linhas do stderr; 20 = cancelado; outros = erro com a mensagem do rsync.
- **Cancelar** manda `SIGTERM`, para o rsync apagar o arquivo parcial; `SIGKILL` só se ele não sair em 5 s.

### 6.6 Perfis de navegadores (tarefa 6)

Catálogo no código. Vale o primeiro caminho que tenha o arquivo `Local State`: uma pasta sem ele é sobra de uma instalação antiga. Do `Local State` (`profile.info_cache`) saem os perfis com nome e conta, para a tela mostrar o que vai ser copiado e quais perfis não têm sincronização (sem conta, o backup é a única cópia).

| id | Navegador | Caminhos do perfil (relativos ao home) |
| --- | --- | --- |
| `brave` | Brave | `.config/BraveSoftware/Brave-Browser`, `.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser` |
| `chrome` | Google Chrome | `.config/google-chrome`, `.var/app/com.google.Chrome/config/google-chrome` |
| `chromium` | Chromium | `.config/chromium`, `snap/chromium/common/chromium`, `.var/app/org.chromium.Chromium/config/chromium` |

- **Navegador aberto:** o Chromium e derivados criam no perfil um link `SingletonLock` apontando para `<host>-<pid>`. O navegador conta como aberto se o link existe e `/proc/<pid>` existe. Isso funciona para deb e snap sem depender do caminho do executável, como o `pgrep` do script. No Flatpak o PID é de outro espaço de processos e não pode ser conferido em `/proc`: ali, o link existir já conta como aberto. Fora do Flatpak, um link com PID morto é resto de travamento e não impede a cópia. O perfil aberto é pulado com o aviso "Feche o Brave para incluir o perfil. Copiar com ele aberto pode corromper o histórico." e o botão "Tentar de novo". O app nunca fecha o navegador.
- **Exclusões**, a lista do script:

  ```
  - Cache/  - Code Cache/  - GPUCache/  - CacheStorage/  - ScriptCache/
  - GrShaderCache/  - GraphiteDawnCache/  - GPUPersistentCache/  - DawnGraphiteCache/
  - DawnWebGPUCache/  - ShaderCache/  - component_crx_cache/  - extensions_crx_cache/
  - Safe Browsing/  - OptimizationGuidePredictionModels/  - optimization_guide_model_store/
  - OnDeviceHeadSuggestModel/  - screen_ai/  - WasmTtsEngine/  - Crash Reports/  - Crashpad/
  - Singleton*  - *.pma
  ```

- Cópia: `rsync -aH --info=progress2 --exclude-from=navegadores.txt [--delete] <perfil>/ <destino>/<pasta do backup>/navegadores/<id>/`.
- Senhas e cookies dependem do keyring do sistema, por isso `.local/share/keyrings` vem marcado nos segredos e o LEIA-ME manda restaurar o keyring antes de abrir os navegadores. Se o usuário marcar navegadores e desligar os segredos (ou desmarcar o keyring), a tela avisa: "Sem o keyring, os perfis voltam sem as senhas salvas."

### 6.7 Pacote de segredos (tarefa 7)

**Catálogo** (relativo ao home), pré-marcado com o que existir na máquina:

```
.ssh  .gitconfig  .gitconfig-*  .gitignore_global  .config/git  .gnupg  .local/share/keyrings
```

`.gitconfig-*` é um glob: cobre arquivos incluídos por `includeIf` (ex.: `.gitconfig-trabalho`). Os arquivos citados em `includeIf.*.path` e `core.excludesfile` do `git config --global` também entram, se existirem dentro do home e não estiverem cobertos por outro item. Os botões "Adicionar arquivo…" e "Adicionar pasta…" incluem itens avulsos (ex.: `private_key.pem`). Avulsos precisam estar **dentro do home**, porque a restauração é `tar x` a partir do home; fora dele, o app recusa com o motivo.

**Comando:**

```
tar czf - -C <home> --exclude=.gnupg/S.* --exclude=.gnupg/*.lock <itens…>
  | gpg --yes --symmetric --cipher-algo AES256 --no-symkey-cache --output <parcial>
```

- **A senha é pedida pelo pinentry do gpg-agent** (a janela do sistema). O app não tem campo de senha e não usa `--passphrase`, `--passphrase-fd` nem `--pinentry-mode loopback`. `--no-symkey-cache` impede o agent de guardar a senha depois.
- **O tar nunca grava em disco.** A saída do tar vai direto para a entrada do gpg (`ProcessRunner.runPiped`, ligação feita no Dart, sem shell), e os dois códigos de saída são conferidos. Os caminhos vão como argumentos de processo. `--pinentry-mode ask` garante a janela mesmo se o `gpg.conf` do usuário tiver `loopback`.
- **Códigos:** gpg que falha com "cancel" no stderr é cancelamento (não erro); "pinentry" ou "Inappropriate ioctl" é falta de pinentry gráfico; tar com código 1 (arquivo mudou durante a leitura) é aviso; tar com código 2 ou mais é falha, porque o pacote ficaria incompleto.
- O gpg grava em `<destino>/.secrets-AAAA-MM-DD.tar.gz.gpg.parcial`, que vira `secrets-AAAA-MM-DD.tar.gz.gpg` só no sucesso. Em falha ou cancelamento o parcial é apagado.
- **Sem pinentry gráfico** (o agent configurado com `pinentry-curses` e o app sem terminal), o gpg falha. A etapa explica: "Não foi possível abrir a janela de senha do sistema. Instale o pacote pinentry-gnome3."
- O texto da seção avisa: "A senha é pedida numa janela do sistema e não fica guardada no app. Sem ela, o arquivo não pode ser aberto. Guarde-a num gerenciador de senhas."

### 6.8 LEIA-ME-RESTAURAR.md (tarefa 8)

Gerado por uma função pura a partir do relatório do backup (o que foi copiado, o que foi pulado). Segue a estrutura do arquivo usado em 08/11/2026, mas genérico, sem e-mails, hosts ou nomes de perfil:

1. **Conteúdo deste disco:** tabela com a pasta do backup (origens e o que não foi copiado), o pacote de segredos (itens incluídos) e a data.
2. **Variável de partida:** `DESTINO="<caminho atual do destino>"`, com a nota de que o caminho muda em outra máquina.
3. **Pacotes:** `sudo apt install rsync gnupg git` (o `git-lfs` só se algum `.gitconfig` incluído tiver `filter "lfs"`).
4. **Segredos** (só se o pacote foi gerado): `cd ~ && gpg -d "$DESTINO/secrets-….tar.gz.gpg" | tar xzf -`, os `chmod` de `.ssh` e `.gnupg` e o comando para conferir o conteúdo (`gpg -d … | tar tzf -`).
5. **Projetos:** `rsync -aH --info=progress2 "$DESTINO/<pasta>/<origem>" <pai original>/` por origem, mais a lembrança de reinstalar as dependências, citando as pastas que não foram copiadas.
6. **Navegadores** (só os copiados): restaurar o keyring antes, fazer logout e login, abrir e fechar o navegador uma vez, fechá-lo e copiar o perfil de volta para o caminho de origem.
7. **Antes de desconectar o disco:** `sync` e `udisksctl unmount -b <dispositivo>`, com o dispositivo vindo do `lsblk`.

### 6.9 Tela Backup (tarefa 9)

Novo destino de navegação `AppDestination.backup` ("Backup", `Symbols.backup_rounded`), **antes de Configurações**: Backup fica em Ctrl+6 e Configurações passa para Ctrl+7 (`_digits` ganha o `digit7`). O `BackupController` (`ChangeNotifier`) vive no nível do app, como o `ScanController`: trocar de tela não interrompe o backup. Fechar a janela interrompe, e a próxima execução retoma de onde parou.

**Configuração** (PageHeader "Backup", subtítulo "Último backup há N dias" ou "Nenhum backup feito ainda"), em SectionCards:

1. **Destino:** discos externos montados em cards com rótulo, sistema de arquivos e espaço livre; "Escolher outra pasta…"; estados "desabilitado com motivo" e "conecte o disco".
2. **Pastas:** lista de origens com remover; "Adicionar pasta…"; após a estimativa, o tamanho de cada uma. Campo "Nome da pasta do backup". Switch "Espelhar" com o aviso de 6.5.
3. **Navegadores:** um checkbox por navegador detectado, com o chip "Aberto" quando for o caso. Nenhum detectado: EmptyState curto.
4. **Segredos:** switch geral, checklist do catálogo existente mais os avulsos, "Adicionar arquivo…" e "Adicionar pasta…", e o aviso sobre a senha.

**Barra de ação no rodapé**, como nas outras telas: "16,3 GB no backup · 1,2 GB a copiar agora", "Calcular" e "Fazer backup" (FilledButton).

**Em andamento:** etapa atual (Preparando, Segredos, Pastas, Navegadores, Guia), barra de progresso, bytes copiados, velocidade, tempo restante e "Cancelar".

**Resumo:** AlertBanner de sucesso, atenção (concluído com avisos) ou erro; uma linha por etapa com o estado e o tamanho; a lista de avisos (arquivos não copiados, navegador aberto com "Tentar de novo", segredos não salvos com "Tentar de novo"); o caminho do backup e do LEIA-ME.

O que o usuário muda na tela é salvo na hora em `BackupSettings` (6.11).

### 6.10 Lembrete na Visão geral (tarefa 10)

- A data do último backup é registrada quando a etapa **Pastas** termina com código 0, 23 ou 24. Segredos ou navegadores pulados não impedem o registro; eles já aparecem no resumo.
- A Visão geral mostra "Último backup há N dias". Antes do primeiro backup, a linha só aparece se houver origens configuradas, para não incomodar quem não usa a feature.
- Passado o limite (padrão 7 dias), aparece um AlertBanner de atenção no estilo do alerta de espaço: "Seu último backup foi há 9 dias", com o botão "Fazer backup", que abre a tela Backup. Sem badge no rail.
- Limite configurável em Configurações; 0 desliga o lembrete. Sem agendamento.

### 6.11 Configurações (tarefa 3)

Novo bloco `BackupSettings` dentro de `Settings`, na chave `backup` do JSON. Arquivos antigos sem a chave carregam os padrões. Imutável, com `copyWith`, `toJson`/`fromJson` e `==`/`hashCode`, como o resto de `settings.dart`.

| Campo | Tipo | Padrão |
| --- | --- | --- |
| `sources` | `List<String>` (caminhos absolutos) | `[]` |
| `targetUuid` | `String?` | `null` |
| `targetLabel` | `String?` (para "conecte o disco X") | `null` |
| `targetRelPath` | `String` (relativo ao ponto de montagem) | `''` |
| `folderName` | `String` | `'backup'` |
| `browsers` | `List<String>?` (ids) | `null` = todos os detectados |
| `secretsEnabled` | `bool` | `true` |
| `secretItems` | `List<String>?` (relativos ao home) | `null` = catálogo existente |
| `mirror` | `bool` | `false` |
| `lastBackupAt` | `DateTime?` | `null` |
| `reminderDays` | `int` | `7` |

`null` em `browsers` e `secretItems` significa "o padrão da máquina". Quando o usuário mexe na lista, ela passa a ser explícita.

## 7. Arquitetura

### 7.1 Arquivos

| Arquivo | Responsabilidade | Tarefa |
| --- | --- | --- |
| `lib/core/process_runner.dart` | streaming de linhas, ambiente e cancelamento com SIGTERM | 2 |
| `lib/settings/settings.dart` | `BackupSettings` | 3 |
| `lib/backup/backup_planner.dart` | exclusões fixas, builds via `git check-ignore`, arquivos de exclusão, estimativa | 4 |
| `lib/backup/disk_targets.dart` | discos (`lsblk`), `findmnt -T`, sistema de arquivos aceito, UUID e caminho relativo | 5 |
| `lib/backup/rsync_runner.dart` | monta o comando, interpreta progresso, `--stats` e códigos de saída | 5 |
| `lib/backup/browser_profiles.dart` | catálogo, detecção, `SingletonLock` | 6 |
| `lib/backup/secrets_archiver.dart` | catálogo, tar ligado ao gpg, arquivo parcial | 7 |
| `lib/backup/restore_readme.dart` | função pura relatório → Markdown | 8 |
| `lib/backup/backup_controller.dart` | estado, validação, etapas, cancelamento, resumo | 9 |
| `lib/ui/pages/backup_page.dart` | tela | 9 |
| `lib/ui/pages/overview_page.dart` | linha e alerta do último backup | 10 |

Os serviços entram em `Services` (`lib/services.dart`) como os demais, construídos com o mesmo `ProcessRunner`.

### 7.2 ProcessRunner com streaming (tarefa 2)

Hoje `run` só devolve a saída no fim. A cópia precisa de progresso em tempo real. A tarefa 2 acrescenta um método que:

- entrega cada linha do stdout assim que chega, separando por `\r` e `\n` (o `progress2` reescreve a linha com `\r`);
- aceita variáveis de ambiente (para o `LC_ALL=C`);
- devolve o código de saída e o stderr completo no fim;
- no cancelamento manda `SIGTERM` e só usa `SIGKILL` se o processo não sair em 5 s;
- tem suporte no `FakeProcessRunner` para roteirizar as linhas de um comando nos testes.

O tar ligado ao gpg (6.7) precisa ligar a saída de um processo à entrada de outro; a forma fica para a tarefa 7, desde que respeite as regras de 6.7 e seja testável com o fake.

### 7.3 Modelos

- `BackupPlan`: origens, destino resolvido, pasta do backup, arquivos de exclusão, espelhar.
- `BackupEstimate`: tamanho total, a copiar agora, número de arquivos, por origem.
- `BackupProgress`: etapa, percentual, bytes, velocidade, tempo restante.
- `BackupReport`: por etapa, o estado (concluída, com avisos, pulada, erro, cancelada), bytes, arquivos e avisos. Alimenta o resumo, o LEIA-ME e a data do último backup.

### 7.4 Testes

- Unitários com `FakeProcessRunner` e diretórios temporários, espelhando `lib/` em `test/`: interpretação do `lsblk`, do `findmnt`, das linhas de progresso e do `--stats`; códigos de saída do rsync; detecção de `SingletonLock`; validações de 6.2; JSON do `BackupSettings` com e sem a chave `backup`; o LEIA-ME para cada combinação de etapas.
- Um teste de integração em `integration/` com `rsync` e `git` reais num diretório temporário: um repositório com `dist/` ignorado e `vendor/bin/` versionado confere que só o primeiro é excluído.
- Nenhum teste escreve fora de diretórios temporários nem chama o `gpg` real.

## 8. Validação e release (tarefa 11)

- Rodar o backup no HD externo com as mesmas origens dos scripts. No mesmo dia, comparar o "Total file size" do `--stats` do app com o do script em `--dry-run`: precisam ser iguais.
- Conferir o pacote de segredos com `gpg -d … | tar tzf -` e um perfil de navegador restaurado numa conta de teste.
- Atualizar o README e a página do GitHub Pages, subir a versão para 0.2.0 e gerar o AppImage com `packaging/appimage/build_appimage.sh 0.2.0`.
- A confirmação visual da tela é do usuário.

## 9. Decisões tomadas na escrita deste documento

Decididas com o usuário em 09/11/2026, durante a escrita:

1. Pasta do backup com nome fixo e reaproveitada (padrão `backup`), não uma pasta com data por execução.
2. Segredos são a primeira etapa, para a senha ser pedida enquanto o usuário está presente.
3. Destino em sistema de arquivos sem permissões Unix (exFAT, NTFS, FAT) é bloqueado com explicação.
4. Origens com o mesmo nome de pasta são rejeitadas.

Decididas pelo autor do documento, e que você pode contestar:

5. Itens de segredo e perfis de navegador dentro de uma origem nunca vão na cópia de pastas (evita `~/.ssh` em texto puro quando a origem é o home).
6. Navegador aberto detectado pelo `SingletonLock` do perfil, não pelo caminho do executável, para cobrir snap e Flatpak. No Flatpak, o lock existir já basta, porque o PID não pode ser conferido.
7. Destino salvo como UUID mais caminho relativo, para sobreviver à mudança do ponto de montagem.
8. `--no-inc-recursive` para o percentual ser real, e `LC_ALL=C` para a saída do rsync ser estável.
9. Cancelamento com `SIGTERM` antes de `SIGKILL`.
10. "Espelhar" usa `--delete`, nunca `--delete-excluded`, e vale também para os navegadores.
11. Itens avulsos de segredo só dentro do home.
12. O gpg grava num arquivo parcial, renomeado só no sucesso; `--no-symkey-cache` para o agent não guardar a senha.
13. A data do último backup é registrada quando a etapa Pastas conclui, mesmo com avisos.
14. A linha do último backup só aparece na Visão geral depois que houver origens configuradas; o lembrete pode ser desligado com 0.
15. Backup fica antes de Configurações no rail (Ctrl+6), e Configurações passa para Ctrl+7.
16. Fechar a janela interrompe o backup; trocar de tela não.
