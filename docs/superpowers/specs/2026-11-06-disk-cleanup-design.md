# disk-cleanup: documento de design

Data: 2026-11-06 · Autor: Ueslei Nascimento · Status: aguardando aprovação

## 1. Intenção

O dono deste projeto sempre fica perdido quando o SSD enche: não sabe o que está ocupando espaço, e restos de builds, caches, Docker e downloads ficam acumulando. Numa varredura manual em 06/11/2026, o SSD de 502,5 GB estava com 8,8% livre. A maior parte do espaço era recuperável: cerca de 27 GB de Docker, 35 GiB de artefatos de build, 36 GiB de caches e 9,5 GiB na lixeira. Achar isso exigiu `du`, `docker system df` e conhecer onde cada ferramenta guarda o cache.

O disk-cleanup é um **gerenciador de espaço em disco para desktop Linux**. Ele mostra o estado do disco, aponta o que mais consome, avisa quando o espaço está baixo e apaga com segurança o que é descartável. Toda exclusão explica o risco antes.

**Sucesso:** abrir o app numa segunda de manhã, entender em segundos o estado do disco e liberar dezenas de GB com poucos cliques, sem medo de apagar algo importante.

## 2. Objetivos

1. **Resumo na primeira tela:** espaço livre, o que mais consome e um alerta quando o espaço estiver baixo. Isso foi pedido explicitamente.
2. **Diretórios mapeados:** o usuário adiciona diretórios para acompanhar o tamanho e o crescimento ao longo do tempo.
3. **Arquivos grandes:** listar os maiores arquivos dentro dos diretórios mapeados, com filtros, e permitir mover para a lixeira ou apagar.
4. **Limpeza:** esvaziar a lixeira, apagar caches de ferramentas e navegadores, e apagar artefatos de build.
5. **Docker:** limpar build cache, containers parados, imagens e volumes sem uso.
6. **Segurança:** toda exclusão abre um diálogo com os riscos, o que some e quanto espaço volta. Operações que exigem root pedem a senha pelo polkit (`pkexec`).
7. **Distribuição:** AppImage publicado em GitHub Releases de um repositório público, com uma página no GitHub Pages para baixar as versões.
8. **Responsividade:** a interface se adapta quando a janela é redimensionada ou maximizada (seção 6.3).

## 3. Não objetivos

- **Sem serviço em segundo plano.** Não há daemon, ícone na bandeja nem notificação do sistema. O alerta só aparece quando o usuário abre o app, que é como ele disse que vai usar.
- **Sem limpeza automática ou agendada.** Nada é apagado sem uma ação explícita e a confirmação no diálogo.
- **Sem suporte a Windows ou macOS.** Linux x86_64 apenas.
- **Sem outros formatos de pacote** (deb, Flatpak, Snap) nesta versão.
- **Sem treemap ou sunburst** nesta versão. A visualização usa barras ordenadas (design system, seção Visualização).
- **Sem gerenciar discos de terceiros ou rede.** O app mostra os volumes montados localmente, mas a limpeza é focada no disco do sistema e no home.

## 4. Antiobjetivos (o que faria o projeto fracassar mesmo funcionando)

- **Apagar algo que o usuário não esperava.** Qualquer exclusão sem diálogo, ou com diálogo vago ("Tem certeza?"), é falha grave.
- **Pedir senha de root à toa**, ou rodar o app inteiro como root.
- **Travar a interface durante a varredura.** Varreduras de centenas de GB precisam rodar fora da thread de UI, com progresso e cancelamento.
- **Números errados ou inconsistentes** entre telas, ou diferentes do sistema sem explicação (ver unidades em 6.4).

## 5. Restrições

- **Stack (decisão do usuário):** Flutter, desktop Linux. Flutter 3.47.5 stable instalado em `~/flutter`. Material 3 nativo; o M3 Expressive não existe no Flutter.
- **Design (decisão do usuário):** Google Material Design 3, seguindo:
  - `docs/references/ui-ux-research.md`, a pesquisa de UI/UX;
  - `docs/references/material-design-3.md`, a referência do M3 com os equivalentes em Flutter;
  - `docs/design-system.md` e `docs/design-system/tokens.css`, o design system do projeto e a fonte de verdade para cores, tipografia, componentes, microcopy e classes de risco. Onde este documento e o design system divergirem, vale este documento, e o design system deve ser atualizado. Os pontos de divergência são: janela mínima, pastas de busca, atalho da Visão geral, pré-seleção de itens com root e senha por lote.
- **Protótipo aprovado pelo usuário em 06/11/2026:** https://claude.ai/artifact/2LoQMkHSnNJfSs2kiMSrL3. São seis telas: Visão geral, Limpeza, Docker, Arquivos grandes, Diretórios e Configurações. O app deve seguir o layout, os fluxos e os textos do protótipo.
- **Idioma da interface:** português brasileiro.
- **Repositório:** `~/ueslei/repositories/disk-cleanup`, que vai virar o repositório público `uesleinasch/disk-cleanup` no GitHub. Os commits não levam trailer de coautoria de IA.
- **Comentários no código** só quando forem indispensáveis (regra global do usuário).
- **Root via pkexec dentro de AppImage:** o ponto de montagem FUSE do AppImage não é acessível ao root. Então nada de dentro do AppImage roda como root. Cada lote confirmado gera **um único** `pkexec /bin/sh -c '<script>'`, e esse script é montado só a partir de um catálogo fixo de modelos de comando no código:
  - `journalctl --vacuum-size=500M`;
  - `apt-get clean`;
  - `snap remove <nome> --revision=<n>`;
  - `du -sxb <caminho>`, só para medir;
  - comandos do docker quando o usuário não está no grupo `docker`.

  Os únicos argumentos variáveis são nomes de snap, revisões e caminhos. Eles saem de saídas do próprio sistema, são validados por regex estrita (`^[a-z0-9-]+$`, `^[0-9]+$`, caminho absoluto existente sem `'`) e sempre vão entre aspas simples. Texto digitado pelo usuário nunca entra no script. O resultado é uma senha por lote, e o diálogo avisa disso antes.

## 6. Comportamento

### 6.1 Telas

As seis telas do protótipo são a especificação visual. O design system (seção 3.3) define o conteúdo de cada uma. Em resumo:

| Tela | Conteúdo essencial |
| --- | --- |
| Visão geral | AlertBanner (atenção ou crítico), card do disco do sistema com a DiskUsageBar (em uso, recuperável, reservado, livre), card "Pode liberar X GB com segurança" que abre o diálogo leve, lista dos 7 maiores consumidores e outros volumes montados |
| Limpeza | Abas Lixeira, Caches e Builds com o total de cada uma. Cada item tem checkbox, etiqueta de risco, aviso de "requer admin" quando for o caso, caminho e observação. A barra de resumo no rodapé abre o diálogo |
| Docker | Totais (imagens, containers, volumes, build cache) e grupos com risco. O diálogo lista o aviso de cada grupo marcado |
| Arquivos grandes | Tabela ordenada por tamanho, filtro por nome, chips de tipo e de "sem acesso há 6 meses". O diálogo Perigoso oferece "Mover para a lixeira" (padrão, com Desfazer) ou "Apagar permanentemente" |
| Diretórios | Lista com tamanho e variação desde a semana anterior, detalhe com os filhos em barras, varredura em andamento, estado "precisa de senha" e o diálogo "Adicionar diretório" |
| Configurações | Limiares de atenção e crítico, "Proteger projetos ativos" (14 dias), pastas de build reconhecidas, tema (sistema, claro ou escuro) e Sobre |

### 6.2 Classes de risco e diálogo

Seguem `docs/design-system.md` (tabela de risco e CleanupConfirmDialog):

- **Seguro:** regenerável. Caches, artefatos de build, build cache do Docker e logs do journal. Abre o diálogo leve, que mostra o que some, quanto volta e "é recriado automaticamente quando necessário", com o botão "Limpar X GB".
- **Atenção:** perde estado que dá para recuperar com esforço. Containers parados, imagens sem uso, volumes e toolchains antigas. Abre o diálogo com a lista e o aviso específico de cada grupo. Nunca vem pré-marcado.
- **Perigoso:** arquivos pessoais e esvaziar a lixeira. Abre o diálogo com botão destrutivo descritivo. Para arquivos pessoais, o padrão é mover para a lixeira, com Desfazer.
- **Requer root:** indicador separado da classe de risco. O diálogo avisa que a senha será pedida; o pkexec é chamado só depois da confirmação.
- **Pré-seleção:** só itens Seguros que **não** exigem root. Não vêm marcados: builds de projetos modificados nos últimos 14 dias, caches de aplicativos em execução (por exemplo, um navegador aberto) e itens de sistema (journal, apt, snap).
- **Atalho da Visão geral:** "Liberar X GB com segurança" soma só os itens pré-selecionados de todas as categorias. O clique abre direto o diálogo leve, que já é a etapa de revisão: ele lista os itens agrupados por categoria e tem o link "Revisar itens", que leva à tela Limpeza. É o comportamento do protótipo aprovado. Como esse atalho nunca inclui itens que exigem root, ele nunca pede senha.

### 6.3 Responsividade (pedido explícito do usuário)

A janela pode ser redimensionada, maximizada e restaurada sem quebrar layout, sem rolagem horizontal da página e sem cortar texto.

- **Tamanho mínimo da janela:** 720 × 560. O design system dizia 960 × 640; reduzi para a interface caber em meia tela num monitor de 1440 px.
- **Faixas de largura** (window size classes do M3):
  - menor que 840 dp: NavigationRail compacto, só ícones com rótulo embaixo (80 dp);
  - de 840 a 1199 dp: rail estendido (220 dp) e um pane;
  - 1200 dp ou mais: rail estendido; Diretórios vira lista e detalhe lado a lado, com pane fixo de 412 dp. As outras telas limitam o conteúdo a 1200 dp e centralizam.
- **Grades e cards** quebram em colunas conforme a largura disponível, como no protótipo com `flex-wrap`. Os 4 cards de totais do Docker passam de 4 para 2 colunas abaixo de 840 dp.
- **Tabelas** (Arquivos grandes) priorizam colunas: em larguras menores, "Último acesso" vai para baixo do nome, e o caminho trunca no meio com tooltip mostrando o caminho completo.
- **Diálogos** têm largura máxima de 560 dp e rolam por dentro quando a altura da janela não comporta.
- **A barra de resumo** fica sempre visível no rodapé e quebra em duas linhas se precisar.
- A janela lembra o último tamanho, a posição e o estado maximizado.

### 6.4 Medidas e unidades

- O espaço do disco vem do sistema (`statvfs` ou equivalente) e é mostrado como capacidade, em uso, reservado pelo sistema e livre. Esses quatro valores somam a capacidade.
- As unidades são decimais (1 GB = 10⁹ bytes), como no Nautilus, com 1 casa decimal, vírgula e unidade sempre visível. O tooltip mostra os bytes exatos. Em Configurações ou Sobre, uma nota explica a diferença para o `df -h` (GiB).
- **"Recuperável"** é a soma dos itens Seguros e Atenção conhecidos na última varredura. **"Pode liberar com segurança"** soma só os Seguros pré-selecionáveis.

### 6.5 Alertas

- Limiares padrão, configuráveis: atenção abaixo de 15% ou 20 GB livres; crítico abaixo de 5% ou 5 GB. Vale o que acontecer primeiro.
- O alerta aparece como AlertBanner na Visão geral e badge no item do rail. "Adiar 1 dia" esconde o banner até o dia seguinte; o badge continua.
- Os limiares valem para o disco do sistema (`/`) e para qualquer outro volume montado que contenha um diretório mapeado.

### 6.6 Varredura

- **Escopo padrão:** no primeiro uso, o app já vem com o home (`~`) mapeado e permite remover depois. "Diretórios mapeados" e "pastas de busca de builds" são **a mesma coisa**: builds e arquivos grandes são procurados dentro dos diretórios mapeados. Na tela de Configurações do design system, "pastas de busca" deixa de existir como conceito separado.
- **Consumidores da Visão geral** (lista dos 7 maiores): entradas de primeiro nível de cada diretório mapeado, com o próprio diretório quando ele não é o home. Também entram o Docker (total do `docker system df`) e os diretórios de sistema legíveis conhecidos (`/var/lib/flatpak`, `/var/lib/snapd`, `/var/log`). Não há sobreposição, porque cada caminho aparece uma vez no nível em que foi listado: um `node_modules` dentro de `~/ueslei` conta dentro de `~/ueslei`. As categorias de limpeza (caches, builds) aparecem no card "Pode liberar", não nessa lista.
- Na abertura do app, a varredura mede o disco (instantâneo), os diretórios mapeados, os caminhos de cache conhecidos, os artefatos de build dentro dos diretórios mapeados e o Docker.
- Roda fora da thread de UI (isolate). Mostra progresso por diretório e pode ser cancelada. A interface aparece na hora com os dados da última varredura salva, marcada com "Atualizado há X".
- Cada varredura gera um snapshot local, guardado em `~/.local/share/disk-cleanup/`. O snapshot alimenta a variação "desde a última semana" e as datas.
- Diretórios sem permissão de leitura (como `/var/lib/docker`) mostram o estado "precisa de senha", com o botão "Medir com senha de administrador". A medição usa pkexec com `du`, só para leitura.
- Symlinks não são seguidos, e a varredura não atravessa pontos de montagem (como `du -x`).

### 6.7 O que o app sabe limpar (catálogo inicial)

| Categoria | Itens | Risco | Root |
| --- | --- | --- | --- |
| Lixeira | `~/.local/share/Trash` (padrão freedesktop) | Perigoso | não |
| Caches de pacotes | uv, pip, npm, yarn, pnpm, bun, Gradle, NuGet, pub, cabal, stack (só o cache de downloads), Cargo registry | Seguro | não |
| Navegadores | caches do Chrome, Chromium, Brave e Firefox (só cache, nunca o perfil) | Seguro | não |
| Ferramentas | navegadores do Playwright, `~/.cache` de apps conhecidos | Seguro | não |
| Builds | `node_modules`, `.angular`, `target` (Rust, só com `Cargo.toml` ao lado), `.stack-work`, `dist-newstyle`, `build` (só em projeto Flutter ou Gradle), `.dart_tool`, `bin` e `obj` (só com `.csproj` ao lado) | Seguro | não |
| Sistema | logs do journal (`journalctl --vacuum-size`), cache do apt (`apt-get clean`), revisões desativadas de snap | Seguro | sim |
| Docker | build cache, containers parados, imagens sem uso, volumes sem uso | Seguro (build cache) e Atenção (o resto) | não, se o usuário estiver no grupo `docker`; senão, pkexec |

Uma pasta de build só é reconhecida quando há o arquivo de projeto correspondente ao lado, para evitar apagar uma pasta `build` qualquer. Em Configurações, o usuário pode adicionar ou remover regras. Cada regra é um par: nome da pasta mais arquivo marcador obrigatório, por exemplo `out` com `package.json`. O marcador aceita um nome exato ou um glob simples (`*.csproj`). Não existe regra sem marcador.

**Fora desta versão:** toolchains antigas (rustup, ghcup, versões do Flutter, nvm). A classe Atenção continua existindo para o Docker.

## 7. Distribuição

- Repositório público `uesleinasch/disk-cleanup`, licença MIT, criado com `gh`, como o usuário pediu. A entrega termina com:
  - o repositório publicado;
  - o GitHub Pages ativo;
  - a tag `v0.1.0` com o Release e o AppImage anexado, depois de verificar que o AppImage abre nesta máquina.
- O GitHub Actions gera o AppImage quando uma tag `v*` é publicada e anexa o arquivo a um GitHub Release.
- O GitHub Pages hospeda uma página estática com a descrição do app e a lista de versões, lida da API de releases do GitHub. A página segue o design system (tokens e tema claro/escuro). O botão principal é "Baixar a versão mais recente".
- O AppImage roda no Ubuntu 22.04 ou mais novo e precisa de `libfuse2` ou do modo `--appimage-extract-and-run`. Isso aparece na página.

## 8. Decisões que tomei e que você pode contestar

1. Janela mínima de 720 × 560, no lugar dos 960 × 640 do design system, por causa do pedido de responsividade.
2. Unidades decimais (GB), com nota explicando a diferença para o `df`.
3. Snapshots locais em `~/.local/share/disk-cleanup/` para mostrar a variação semanal.
4. Uma pasta de build só é reconhecida com o arquivo de projeto ao lado.
5. Root apenas por pkexec com binários do sistema e argumentos fixos.
6. Licença MIT.
7. Interface só em português brasileiro.
8. Uma senha por lote: `pkexec /bin/sh -c` com script montado só a partir de modelos fixos e argumentos validados.
9. O home vem mapeado por padrão, e "diretórios mapeados" e "pastas de busca de builds" são a mesma coisa.
10. A lista de consumidores usa o primeiro nível dos diretórios mapeados, mais Docker e diretórios de sistema conhecidos.
11. Itens que exigem root nunca vêm pré-marcados nem entram no atalho "Liberar com segurança".
12. Regras de pasta de build sempre têm arquivo marcador.
13. Toolchains antigas ficam para uma versão futura.

## 9. Deixado para quem for construir

- Arquitetura interna do app: camadas, gerenciamento de estado, estrutura de pastas e formato do snapshot (JSON ou SQLite).
- Como medir o disco: `statvfs` via FFI ou leitura do `df`.
- Integração com Docker: CLI com saída JSON ou API pelo socket.
- Mecanismo para mover arquivos para a lixeira e desfazer: `gio trash` ou implementar a especificação freedesktop.
- Ferramenta para gerar o AppImage (por exemplo, appimagetool ou appimage-builder) e a estrutura do workflow.
- Estratégia de testes, desde que cubra classificação de risco, detecção de builds, cálculo de alertas e o caminho de exclusão com diretórios temporários. Nenhum teste pode apagar nada fora de um diretório temporário.
