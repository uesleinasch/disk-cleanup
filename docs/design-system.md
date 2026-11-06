# Design system do disk-cleanup

Design system do **disk-cleanup**, gerenciador de espaço em disco para desktop Linux escrito em Flutter 3.47 com **Material 3 nativo (baseline)** e distribuído como AppImage. O M3 Expressive não existe no Flutter e não é usado aqui `[M3 §1]`.

Este documento define o que vale para o app e para o protótipo HTML. Os tokens CSS estão em [`design-system/tokens.css`](design-system/tokens.css).

**Como ler as citações.** `[UX §6.2]` aponta para a seção 6.2 de [`references/ui-ux-research.md`](references/ui-ux-research.md); `[M3 §10.12]` aponta para a seção 10.12 de [`references/material-design-3.md`](references/material-design-3.md). Onde o texto diz **Decisão**, a escolha é do projeto e prevalece sobre a pesquisa; as divergências estão listadas na [seção 10](#10-divergências-entre-decisões-e-pesquisa).

## Sumário

1. [Princípios do produto](#1-princípios-do-produto)
2. [Fundamentos](#2-fundamentos)
3. [Layout e navegação](#3-layout-e-navegação)
4. [Componentes](#4-componentes)
5. [Padrões de interação](#5-padrões-de-interação)
6. [Conteúdo e microcopy](#6-conteúdo-e-microcopy)
7. [Acessibilidade](#7-acessibilidade)
8. [Mapeamento para Flutter](#8-mapeamento-para-flutter)
9. [Checklist de revisão](#9-checklist-de-revisão)
10. [Divergências entre decisões e pesquisa](#10-divergências-entre-decisões-e-pesquisa)
11. [Apêndice: geração das cores](#11-apêndice-geração-das-cores)

---

## 1. Princípios do produto

1. **O número que importa vem primeiro.** Ao abrir o app, a pessoa vê o espaço livre e o estado do disco antes de qualquer outra coisa; detalhes ficam um nível abaixo, por divulgação progressiva. Base: hierarquia visual e ordem de leitura `[UX §4.1]`, dashboards para consumo rápido `[UX §4.4]`, heurística 8 `[UX §2]`.
2. **O risco é sempre visível e nunca só em cor.** Todo item que pode ser apagado mostra a classe de risco (Seguro, Atenção, Perigoso) com ícone, texto e cor, e o indicador "requer root" quando for o caso. Só o que é regenerável vem pré-selecionado. Base: prevenção de erros `[UX §2]`, matriz de risco `[UX §6.2]`, WCAG 1.4.1 `[UX §9.2]`.
3. **Específico e honesto com os números.** Todo tamanho tem unidade, toda estimativa diz que é estimativa, o que foi liberado de fato aparece depois da limpeza e o que não pôde ser lido aparece como desconhecido, nunca como 0 B. Base: correspondência com o mundo real `[UX §2]`, estimado x liberado `[UX §6.3]`, permissões `[UX §8.5]`.
4. **A pessoa mantém o controle.** Varreduras e limpezas podem ser canceladas, movimentações para a lixeira podem ser desfeitas, e diálogos só aparecem em resposta direta a uma ação. Base: controle e liberdade `[UX §2]`, ações destrutivas `[UX §6.1]`, tempos de resposta `[UX §8.1]`.
5. **Discreto por padrão.** O app não roda em segundo plano nem envia notificações do sistema; alertas vivem dentro do app, e destaque visual fica reservado ao que exige atenção. Base: respeitar tempo e atenção `[UX §10.1]`, efeito Von Restorff `[UX §3]`, fadiga de alertas `[UX §7.2]`. **Decisão:** sem daemon e sem notificação do sistema.

---

## 2. Fundamentos

### 2.1 Cor

#### Origem e algoritmo

| Item | Valor |
| --- | --- |
| Seed (source color) | `#006A6A` (teal); HCT: hue 196,6, chroma 34,7, tone 40,2 |
| Algoritmo | `material-color-utilities` (TypeScript 0.4.0), `SchemeTonalSpot`, `specVersion: '2021'`, `contrastLevel: 0.0` |
| Equivalente Flutter | `ColorScheme.fromSeed(seedColor: Color(0xFF006A6A), dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot)` `[M3 §3.5]` |
| Tipo de esquema | Estático gerado de uma cor fixa da marca, claro e escuro `[M3 §3.5]` |

A spec 2021 é a usada pelo Flutter (`DEFAULT_SPEC_VERSION = '2021'` na biblioteca). Os valores abaixo saíram do script do [apêndice](#11-apêndice-geração-das-cores); nenhum hex foi escrito à mão. No app, use as constantes literais da [seção 8.2](#82-colorscheme), e um teste deve compará-las com `ColorScheme.fromSeed` para detectar diferença de versão da biblioteca.

Paletas tonais resultantes (HCT):

| Paleta | Hue | Chroma |
| --- | --- | --- |
| primary | 196,6 | 36 |
| secondary | 196,6 | 16 |
| tertiary | 256,6 | 24 |
| neutral | 196,6 | 6 |
| neutral variant | 196,6 | 8 |
| error | 25 | 84 |

#### Color roles (claro e escuro)

Coluna "Tom" é o tom HCT na paleta de origem. Em Flutter o nome é o mesmo do papel, exceto `inverseOnSurface`, que vira `onInverseSurface` `[M3 §14.1]`.

| Papel (Flutter) | Token CSS | Claro: tom | Claro: hex | Escuro: tom | Escuro: hex |
| --- | --- | --- | --- | --- | --- |
| `primary` | `--md-sys-color-primary` | 40 | `#006A6A` | 80 | `#80D5D4` |
| `onPrimary` | `--md-sys-color-on-primary` | 100 | `#FFFFFF` | 20 | `#003737` |
| `primaryContainer` | `--md-sys-color-primary-container` | 90 | `#9CF1F0` | 30 | `#004F4F` |
| `onPrimaryContainer` | `--md-sys-color-on-primary-container` | 30 | `#004F4F` | 90 | `#9CF1F0` |
| `primaryFixed` | `--md-sys-color-primary-fixed` | 90 | `#9CF1F0` | 90 | `#9CF1F0` |
| `primaryFixedDim` | `--md-sys-color-primary-fixed-dim` | 80 | `#80D5D4` | 80 | `#80D5D4` |
| `onPrimaryFixed` | `--md-sys-color-on-primary-fixed` | 10 | `#002020` | 10 | `#002020` |
| `onPrimaryFixedVariant` | `--md-sys-color-on-primary-fixed-variant` | 30 | `#004F4F` | 30 | `#004F4F` |
| `inversePrimary` | `--md-sys-color-inverse-primary` | 80 | `#80D5D4` | 40 | `#006A6A` |
| `secondary` | `--md-sys-color-secondary` | 40 | `#4A6363` | 80 | `#B0CCCB` |
| `onSecondary` | `--md-sys-color-on-secondary` | 100 | `#FFFFFF` | 20 | `#1B3534` |
| `secondaryContainer` | `--md-sys-color-secondary-container` | 90 | `#CCE8E7` | 30 | `#324B4B` |
| `onSecondaryContainer` | `--md-sys-color-on-secondary-container` | 30 | `#324B4B` | 90 | `#CCE8E7` |
| `secondaryFixed` | `--md-sys-color-secondary-fixed` | 90 | `#CCE8E7` | 90 | `#CCE8E7` |
| `secondaryFixedDim` | `--md-sys-color-secondary-fixed-dim` | 80 | `#B0CCCB` | 80 | `#B0CCCB` |
| `onSecondaryFixed` | `--md-sys-color-on-secondary-fixed` | 10 | `#051F1F` | 10 | `#051F1F` |
| `onSecondaryFixedVariant` | `--md-sys-color-on-secondary-fixed-variant` | 30 | `#324B4B` | 30 | `#324B4B` |
| `tertiary` | `--md-sys-color-tertiary` | 40 | `#4B607C` | 80 | `#B3C8E8` |
| `onTertiary` | `--md-sys-color-on-tertiary` | 100 | `#FFFFFF` | 20 | `#1C314B` |
| `tertiaryContainer` | `--md-sys-color-tertiary-container` | 90 | `#D3E4FF` | 30 | `#334863` |
| `onTertiaryContainer` | `--md-sys-color-on-tertiary-container` | 30 | `#334863` | 90 | `#D3E4FF` |
| `tertiaryFixed` | `--md-sys-color-tertiary-fixed` | 90 | `#D3E4FF` | 90 | `#D3E4FF` |
| `tertiaryFixedDim` | `--md-sys-color-tertiary-fixed-dim` | 80 | `#B3C8E8` | 80 | `#B3C8E8` |
| `onTertiaryFixed` | `--md-sys-color-on-tertiary-fixed` | 10 | `#041C35` | 10 | `#041C35` |
| `onTertiaryFixedVariant` | `--md-sys-color-on-tertiary-fixed-variant` | 30 | `#334863` | 30 | `#334863` |
| `error` | `--md-sys-color-error` | 40 | `#BA1A1A` | 80 | `#FFB4AB` |
| `onError` | `--md-sys-color-on-error` | 100 | `#FFFFFF` | 20 | `#690005` |
| `errorContainer` | `--md-sys-color-error-container` | 90 | `#FFDAD6` | 30 | `#93000A` |
| `onErrorContainer` | `--md-sys-color-on-error-container` | 30 | `#93000A` | 90 | `#FFDAD6` |
| `surface` | `--md-sys-color-surface` | 98 | `#F4FBFA` | 6 | `#0E1514` |
| `onSurface` | `--md-sys-color-on-surface` | 10 | `#161D1D` | 90 | `#DDE4E3` |
| `onSurfaceVariant` | `--md-sys-color-on-surface-variant` | 30 | `#3F4948` | 80 | `#BEC9C8` |
| `surfaceDim` | `--md-sys-color-surface-dim` | 87 | `#D5DBDA` | 6 | `#0E1514` |
| `surfaceBright` | `--md-sys-color-surface-bright` | 98 | `#F4FBFA` | 24 | `#343A3A` |
| `surfaceContainerLowest` | `--md-sys-color-surface-container-lowest` | 100 | `#FFFFFF` | 4 | `#090F0F` |
| `surfaceContainerLow` | `--md-sys-color-surface-container-low` | 96 | `#EFF5F4` | 10 | `#161D1D` |
| `surfaceContainer` | `--md-sys-color-surface-container` | 94 | `#E9EFEE` | 12 | `#1A2121` |
| `surfaceContainerHigh` | `--md-sys-color-surface-container-high` | 92 | `#E3E9E9` | 17 | `#252B2B` |
| `surfaceContainerHighest` | `--md-sys-color-surface-container-highest` | 90 | `#DDE4E3` | 22 | `#2F3636` |
| `inverseSurface` | `--md-sys-color-inverse-surface` | 20 | `#2B3231` | 90 | `#DDE4E3` |
| `onInverseSurface` | `--md-sys-color-inverse-on-surface` | 95 | `#ECF2F1` | 20 | `#2B3231` |
| `outline` | `--md-sys-color-outline` | 50 | `#6F7979` | 60 | `#889392` |
| `outlineVariant` | `--md-sys-color-outline-variant` | 80 | `#BEC9C8` | 30 | `#3F4948` |
| `shadow` | `--md-sys-color-shadow` | 0 | `#000000` | 0 | `#000000` |
| `scrim` | `--md-sys-color-scrim` | 0 | `#000000` | 0 | `#000000` |
| `surfaceTint` | `--md-sys-color-surface-tint` | 40 | `#006A6A` | 80 | `#80D5D4` |
| `surfaceVariant` (deprecado) | `--md-sys-color-surface-variant` | 90 | `#DAE5E4` | 30 | `#3F4948` |

`background`/`onBackground` e `surfaceVariant` existem só no CSS por compatibilidade; no Flutter use `surface`, `onSurface` e `surfaceContainerHighest` `[M3 §3.2]`.

#### Uso dos papéis no produto

| Elemento | Papel |
| --- | --- |
| Fundo da janela, rail, app bar em repouso | `surface` |
| Cards de lista e da Visão geral | `Card.outlined` (`surface` + borda `outlineVariant`); cards de destaque com `surfaceContainerLow` |
| Diálogos | `surfaceContainerHigh` `[M3 §10.10]` |
| Menus, tooltip rico | `surfaceContainer` `[M3 §10.14]` |
| Item ativo do rail, abas selecionadas | `secondaryContainer` / `onSecondaryContainer` `[M3 §9.1]` |
| Ação principal da tela | `primary` / `onPrimary` (um único `FilledButton` por tela `[M3 §10.6]`) |
| Ação destrutiva irreversível | `error` / `onError` (somente no botão de confirmação do diálogo Perigoso) |
| Segmento "usado" da barra de disco e barras de consumidores | `primary` |
| Segmento "recuperável estimado" | `tertiary` com listras `tertiaryContainer` |
| Segmento "livre" e trilhas | `surfaceContainerHighest` com borda `outline` |
| SnackBar | `inverseSurface`, texto `onInverseSurface`, ação `inversePrimary` `[M3 §10.11]` |
| Divisores e borda de card | `outlineVariant`; nunca `outline` `[M3 §3.2]` |
| Borda de campo, borda de barra de dados | `outline` (garante 3:1) |
| Texto secundário (caminhos, datas, legendas) | `onSurfaceVariant` |

Regras:

- Sempre parear container com o "on" correspondente; nada de `primaryContainer` com `onSurface` `[M3 §3.2]`.
- Widgets nunca usam hex: só `ColorScheme` e `SeverityColors`.
- `success` e `primary` têm o mesmo tom e hue próximos (contraste 1,00:1 entre si). Por isso `success` nunca aparece sem ícone e texto, e nunca ao lado de `primary` como se fossem categorias diferentes de um gráfico.

### 2.2 Cores de severidade

O M3 não tem papéis de aviso ou sucesso; o caminho coerente é custom color harmonizada com a seed, com o quarteto de papéis em claro e escuro, guardada numa `ThemeExtension` `[M3 §3.6]` `[M3 §14.2]`. Crítico usa o `error` nativo.

Geração: `Blend.harmonize(origem, seed)` (rotaciona o hue até 15° na direção da seed), depois `TonalPalette.fromHueAndChroma(hue, max(48, chroma))`, a mesma regra do Material Theme Builder para custom colors. Tons usados iguais aos de `primary` no esquema: claro 40/100/90/30, escuro 80/20/30/90.

| Severidade | Origem | Harmonizada | Hue HCT |
| --- | --- | --- | --- |
| `success` | `#2E7D32` | `#007E4E` | 145,6 → 160,4 |
| `warning` | `#F9A825` | `#E5B118` | 72,8 → 87,7 |
| crítico (`error`) | paleta fixa do M3 | | 25 |

| Papel (Flutter `SeverityColors`) | Token CSS | Claro | Escuro |
| --- | --- | --- | --- |
| `success` | `--dc-color-success` | `#006D43` | `#76DAA1` |
| `onSuccess` | `--dc-color-on-success` | `#FFFFFF` | `#003920` |
| `successContainer` | `--dc-color-success-container` | `#92F7BC` | `#005231` |
| `onSuccessContainer` | `--dc-color-on-success-container` | `#005231` | `#92F7BC` |
| `warning` | `--dc-color-warning` | `#775A00` | `#F4BF2A` |
| `onWarning` | `--dc-color-on-warning` | `#FFFFFF` | `#3F2E00` |
| `warningContainer` | `--dc-color-warning-container` | `#FFDF99` | `#5A4300` |
| `onWarningContainer` | `--dc-color-on-warning-container` | `#5A4300` | `#FFDF99` |
| crítico | `--dc-color-critical*` (aliases de `--md-sys-color-error*`) | `#BA1A1A` / `#FFDAD6` | `#FFB4AB` / `#93000A` |

Mapeamento de significado (sempre com ícone + texto + cor `[UX §9.2]`):

| Significado | Cor | Ícone (Material Symbols Rounded) | Texto |
| --- | --- | --- | --- |
| Disco saudável | `success` | `check_circle` | "Espaço saudável" |
| Disco em atenção | `warning` / `warningContainer` | `warning` | "Pouco espaço" |
| Disco crítico | `error` / `errorContainer` | `error` | "Espaço crítico" |
| Item Seguro | `successContainer` | `check_circle` | "Seguro" |
| Item Atenção | `warningContainer` | `warning` | "Atenção" |
| Item Perigoso | `errorContainer` | `dangerous` | "Perigoso" |
| Resultado com sucesso | (sem cor; SnackBar não tem ícone `[M3 §10.11]`) | | "12,4 GB liberados." |

### 2.3 Contraste verificado

Razões WCAG calculadas sobre os hex gerados (luminância relativa WCAG 2.x). Mínimos: 4,5:1 para texto, 3:1 para elementos gráficos e componentes `[UX §9.1]` `[M3 §12]`.

| Par | Uso | Claro | Escuro | Mínimo |
| --- | --- | --- | --- | --- |
| `onSurface` / `surface` | texto principal | 16,31 | 14,33 | 4,5 |
| `onSurfaceVariant` / `surface` | texto secundário | 8,87 | 10,90 | 4,5 |
| `onSurfaceVariant` / `surfaceContainerHighest` | texto em trilha | 7,21 | 7,27 | 4,5 |
| `primary` / `surface` | texto e ícone de destaque | 6,12 | 10,90 | 4,5 |
| `onPrimary` / `primary` | rótulo de `FilledButton` | 6,42 | 7,73 | 4,5 |
| `onPrimaryContainer` / `primaryContainer` | | 7,28 | 7,28 | 4,5 |
| `onSecondaryContainer` / `secondaryContainer` | item ativo do rail | 7,25 | 7,25 | 4,5 |
| `primary` / `surfaceContainerHigh` | `TextButton` em diálogo | 5,23 | 8,49 | 4,5 |
| `error` / `surfaceContainerHigh` | texto de erro em diálogo | 5,26 | 8,48 | 4,5 |
| `onError` / `error` | botão "Apagar 23,3 GB" | 6,46 | 7,72 | 4,5 |
| `onErrorContainer` / `errorContainer` | banner crítico, chip Perigoso | 7,24 | 7,24 | 4,5 |
| `error` / `surface` | texto e ícone de erro | 6,16 | 10,89 | 4,5 |
| `onSuccess` / `success` | | 6,42 | 7,67 | 4,5 |
| `onSuccessContainer` / `successContainer` | chip Seguro | 7,22 | 7,22 | 4,5 |
| `success` / `surface` | texto e ícone "Espaço saudável" | 6,13 | 10,84 | 4,5 |
| `success` / `surfaceContainerLow` | idem em card de destaque | 5,82 | 10,03 | 4,5 |
| `onWarning` / `warning` | badge de atenção | 6,47 | 7,70 | 4,5 |
| `onWarningContainer` / `warningContainer` | banner de atenção, chip Atenção | 7,27 | 7,27 | 4,5 |
| `warning` / `surface` | texto e ícone de atenção | 6,17 | 10,86 | 4,5 |
| `warning` / `surfaceContainerLow` | idem em card de destaque | 5,86 | 10,05 | 4,5 |
| ícone `success` / `successContainer` | ícone no chip | 4,97 | 5,47 | 3 |
| ícone `warning` / `warningContainer` | ícone no chip | 5,01 | 5,51 | 3 |
| ícone `error` / `errorContainer` | ícone no chip | 5,00 | 5,51 | 3 |
| `onInverseSurface` / `inverseSurface` | texto da SnackBar | 11,56 | 10,15 | 4,5 |
| `inversePrimary` / `inverseSurface` | ação "Desfazer" | 7,73 | 4,98 | 4,5 |
| `outline` / `surface` | borda de barra, campo | 4,27 | 5,84 | 3 |
| `outline` / `surfaceContainerLow` | borda em card de destaque | 4,06 | 5,41 | 3 |
| `outline` / `surfaceContainerHighest` | borda x segmento livre | 3,47 | 3,90 | 3 |
| `primary` / `surfaceContainerHighest` | usado x livre; barra x trilha | 4,98 | 7,28 | 3 |
| `tertiary` / `surfaceContainerHighest` | recuperável x livre | 4,99 | 7,25 | 3 |
| `warning` / `surfaceContainerHighest` | usado (atenção) x livre | 5,01 | 7,25 | 3 |
| `error` / `surfaceContainerHighest` | usado (crítico) x livre | 5,01 | 7,27 | 3 |
| `tertiary` / `tertiaryContainer` | listras do recuperável | 5,00 | 5,49 | 3 |
| `primary` / `tertiary` | usado x recuperável | **1,00** | **1,00** | 3 |
| `surfaceContainerHighest` / `surface` | trilha livre x fundo | **1,23** | **1,50** | 3 |

Os dois pares em negrito falham por natureza (mesmo tom). A [DiskUsageBar](#41-diskusagebar) compensa como pede `[UX §9.1]` e `[UX §5.3]`: separador de 2dp entre segmentos, padrão de listras no recuperável, borda `outline` ao redor da barra e valores escritos na legenda. Severidade nunca depende só desses pares.

### 2.4 Tipografia

| Item | Decisão |
| --- | --- |
| Fonte de interface | **Roboto**, embutida como asset (Regular 400, Medium 500, Bold 700); não depender da fonte do sistema `[M3 §4.2]` |
| Fonte monoespaçada | **Roboto Mono** (400, 500) para tamanhos em listas, caminhos e comandos `[M3 §4.1]` `[UX §4.2]` |
| Algarismos | `FontFeature.tabularFigures()` em todo número de tamanho, inclusive no número grande em Roboto `[UX §4.2]` |
| Escala | type scale baseline do M3, sem alterações `[M3 §4.2]` |
| Capitalização | de frase em todos os rótulos `[UX §4.2]` |

Uso da escala no produto (no máximo 3 a 4 tamanhos por tela `[UX §4.2]`):

| Estilo | px / altura / peso | Uso no disk-cleanup |
| --- | --- | --- |
| `displaySmall` | 36 / 44 / 400 | Espaço livre na Visão geral ("52,1 GB"), com algarismos tabulares |
| `headlineSmall` | 24 / 32 / 400 | Título de EmptyState e PermissionState |
| `titleLarge` | 22 / 28 / 400 | Título da página na app bar |
| `titleMedium` | 16 / 24 / 500 | Título de card e de seção; total no CleanupSummaryBar |
| `titleSmall` | 14 / 20 / 500 | Cabeçalho de coluna de tabela |
| `bodyLarge` | 16 / 24 / 400 | Texto de diálogo e banner |
| `bodyMedium` | 14 / 20 / 400 | Corpo, título de linha de lista |
| `bodySmall` | 12 / 16 / 400 | Metadados (data, "Atualizado há 3 min"), legenda da barra |
| `labelLarge` | 14 / 20 / 500 | Botões, abas |
| `labelMedium` | 12 / 16 / 500 | RiskChip, indicador "requer root", rótulos do rail |
| `labelSmall` | 11 / 16 / 500 | Badge |

Os demais estilos (`displayLarge`, `displayMedium`, `headlineLarge`, `headlineMedium`) ficam disponíveis, sem uso previsto.

Estilos monoespaçados do produto (`DcTextStyles`):

| Nome | Base | Fonte | px / altura / peso | Uso |
| --- | --- | --- | --- | --- |
| `monoBody` | `bodyMedium` | Roboto Mono | 14 / 20 / 400, tracking 0 | Caminhos em listas e diálogos, comandos para copiar |
| `monoBodySmall` | `bodySmall` | Roboto Mono | 12 / 16 / 400, tracking 0 | Caminho atual na varredura, legenda da barra |
| `monoLabel` | `labelLarge` | Roboto Mono | 14 / 20 / 500, tracking 0 | Coluna de tamanho alinhada à direita |
| `numericHero` | `displaySmall` | Roboto | 36 / 44 / 400 + tabular | Espaço livre |

Caminhos longos usam truncamento no meio, preservando início e fim (`~/projetos/…/node_modules`), com o caminho completo no tooltip `[UX §4.2]`.

### 2.5 Espaçamento e grid

Grid de 4dp, com 8dp como passo principal `[UX §4.3]` `[M3 §8.3]`. Tokens `--dc-space-N` valem N × 4px.

| Token CSS | Flutter (`DcSpacing`) | Valor | Uso típico |
| --- | --- | --- | --- |
| `--dc-space-1` | `space1` | 4 | Ícone ↔ texto em chips, ajustes finos |
| `--dc-space-2` | `space2` | 8 | Gap entre elementos relacionados; espaço mínimo entre alvos `[M3 §12]` |
| `--dc-space-3` | `space3` | 12 | Gap entre linhas da legenda, padding de chip |
| `--dc-space-4` | `space4` | 16 | Padding interno de card e de linha de lista |
| `--dc-space-5` | `space5` | 20 | Raro |
| `--dc-space-6` | `space6` | 24 | Margem da página, gutter entre cards, padding de diálogo |
| `--dc-space-8` | `space8` | 32 | Separação entre seções |
| `--dc-space-10` | `space10` | 40 | Respiro acima de EmptyState |
| `--dc-space-12` | `space12` | 48 | Raro |
| `--dc-space-16` | `space16` | 64 | Raro |

Regras:

- Margem da página: 24dp em todas as larguras suportadas (a janela mínima já cai no breakpoint expanded) `[M3 §8.1]`.
- Grid de cards da Visão geral: 12 colunas fluidas com gutter de 24dp; conteúdo limitado a 1200dp de largura e alinhado à esquerda.
- Proximidade indica relação: o tamanho fica colado ao nome do item; seções diferentes ficam a 32dp `[UX §4.3]`.

### 2.6 Shape

Escala baseline; os tokens Expressive (`large-increased`, `extra-large-increased`, `extra-extra-large`) não são usados `[M3 §5.1]`.

| Token | Valor | Onde no disk-cleanup |
| --- | --- | --- |
| `corner-none` | 0 | Rail, app bar, abas, progress indicator |
| `corner-extra-small` | 4 | DiskUsageBar, barras do ConsumerBarList, SnackBar, tooltip, menu |
| `corner-small` | 8 | RiskChip, indicador "requer root", chips de filtro |
| `corner-medium` | 12 | Cards, AlertBanner (quando dentro do conteúdo), bloco de comando no PermissionState |
| `corner-large` | 16 | Container de lista segmentada (se usado) |
| `corner-extra-large` | 28 | CleanupConfirmDialog e demais diálogos |
| `corner-full` | 9999 | Botões, icon buttons, badge, indicador ativo do rail |

Não aplicar `large` ou `full` em componentes densos em informação, como cards e barras de dados `[M3 §5.2]`.

### 2.7 Elevation

Hierarquia por cor tonal (`surfaceContainer*`); sombra só onde o componente M3 já usa `[M3 §6.1]`.

| Nível | dp | Uso |
| --- | --- | --- |
| level0 | 0 | Rail, app bar em repouso, cards (outlined), botões, AlertBanner |
| level1 | 1 | Não usado em repouso (elevated card evitado) |
| level2 | 3 | Menus, tooltip rico, app bar ao rolar (`scrolledUnderElevation`) |
| level3 | 6 | Diálogos, SnackBar |
| level4 / level5 | 8 / 12 | Reservados para hover e drag dos componentes M3 |

As sombras CSS do protótipo (`--dc-elevation-shadow-level*`) vêm do kit de design do M3 e não são tokens oficiais `[M3 §15.4]`.

### 2.8 Motion

Easing e duração do M3 baseline (springs são Expressive e não existem no Flutter) `[M3 §7.1]`.

| Transição | Easing | Duração | Flutter |
| --- | --- | --- | --- |
| Troca de destino no rail (fade-through do conteúdo) | emphasized | 300ms (`medium2`) | `Curves.easeInOutCubicEmphasized`, `Durations.medium2` |
| AlertBanner entrando | emphasized decelerate | 400ms | `Easing.emphasizedDecelerate`, `Durations.medium4` |
| AlertBanner saindo, item removido da lista após limpeza | emphasized accelerate | 200ms | `Easing.emphasizedAccelerate`, `Durations.short4` |
| Barras crescendo ao atualizar valores | standard | 300ms | `Easing.standard`, `Durations.medium2` |
| Checkbox, switch, chip | standard | 200ms | padrão dos componentes `[M3 §7.4]` |
| Avanço de progresso | linear, sem animação extra entre atualizações | | `LinearProgressIndicator(value:)` |
| Expandir lista no diálogo | standard decelerate | 250ms | `Easing.standardDecelerate`, `Durations.medium1` |

Regras: nada anima em loop além de progresso indeterminado; com `MediaQuery.disableAnimationsOf(context)` (ou `prefers-reduced-motion` no protótipo) as durações vão a zero.

### 2.9 State layers e foco

| Estado | Opacidade da state layer | Token |
| --- | --- | --- |
| Hover | 8% | `--md-sys-state-hover-state-layer-opacity` |
| Focus | 10% | `--md-sys-state-focus-state-layer-opacity` |
| Pressed | 10% | `--md-sys-state-pressed-state-layer-opacity` |
| Dragged | 16% | `--md-sys-state-dragged-state-layer-opacity` |
| Disabled | conteúdo 38%, container `onSurface` 12% | `--md-sys-state-disabled-*` |

Fonte: `[M3 §9.1]`. A cor da camada é a cor do conteúdo (o "on" do container). Item selecionado (rail, aba) troca o container para `secondaryContainer` em vez de usar camada. Linhas selecionadas de lista (checkbox marcado) não mudam de fundo: o checkbox comunica a seleção, e o fundo fica livre para hover e foco.

Indicador de foco: anel de 3dp, offset externo de 2dp, cor `secondary` `[M3 §9.2]`. Nunca remover o contorno de foco `[UX §9.3]`. Em Flutter, os componentes M3 já desenham foco; widgets próprios (barras clicáveis, linhas de tabela) usam `FocusableActionDetector` e desenham o anel.

### 2.10 Ícones

**Decisão:** Material Symbols **Rounded**, fonte variável, `FILL 0` em repouso e `FILL 1` para selecionado (rail), `wght 400`, `GRAD 0`, `opsz` igual ao tamanho `[M3 §13.1]`.

Tamanhos: 24dp padrão; 20dp em listas densas, botões e app bar de desktop; 18dp dentro de RiskChip e do indicador "requer root" (container de 24dp); 48dp em EmptyState e PermissionState `[M3 §13.1]`.

No Flutter, `Icons.*` usa a fonte legada Material Icons `[M3 §13.3]`. Use o pacote `material_symbols_icons` (`Symbols.<nome>` com `Icon(..., fill:, weight:)`) ou empacote a fonte variável Rounded com um subconjunto de glifos. O pacote é da comunidade; valide licença e tamanho do asset antes de adotar.

| Contexto | Ícone |
| --- | --- |
| Visão geral | `space_dashboard` |
| Diretórios | `folder_special` |
| Arquivos grandes | `description` |
| Limpeza | `cleaning_services` |
| Docker | `deployed_code` (alternativa: `layers`) |
| Configurações | `settings` |
| Atualizar | `refresh` |
| Menu principal | `more_vert` |
| Seguro / saudável | `check_circle` |
| Atenção | `warning` |
| Perigoso | `dangerous` |
| Crítico (disco) | `error` |
| Requer root | `admin_panel_settings` |
| Sem permissão de leitura | `lock` |
| Lixeira | `delete` (mover), `delete_forever` (permanente) |
| Restaurar | `restore_from_trash` |
| Caches | `cached` |
| Builds | `build` |
| Abrir no gerenciador de arquivos | `folder_open` |
| Copiar caminho ou comando | `content_copy` |
| Informação | `info` |

Os nomes `space_dashboard`, `folder_special`, `deployed_code`, `cached` e `dangerous` não constam da lista conferida em `[M3 §13.4]`; confirme cada um no catálogo do Material Symbols ao montar o subconjunto da fonte.

### 2.11 Densidade e alvos

**Decisão:** densidade padrão no app inteiro e `VisualDensity.compact` em listas e tabelas.

| Item | Valor | Fonte |
| --- | --- | --- |
| `ThemeData.visualDensity` | `VisualDensity.standard` | `[M3 §8.3]` |
| `ListTileThemeData.visualDensity` | `VisualDensity.compact` (linha de 1 linha: 48dp; 2 linhas: 64dp) | Decisão |
| Linha de tabela própria | 44dp | `[M3 §12]` |
| Alvo mínimo de ponteiro | 44 × 44dp (área clicável, não o desenho) | `[M3 §12]` |
| Piso absoluto | 24 × 24dp com espaçamento equivalente (WCAG 2.5.8) | `[UX §9.3]` |
| Espaço entre alvos | 8dp ou mais | `[M3 §12]` |
| Icon buttons | container 40dp, `MaterialTapTargetSize.padded` (alvo 48dp) | `[M3 §10.7]` |
| Checkbox em linha | a linha inteira é o alvo (`CheckboxListTile` ou `InkWell` na linha) | `[M3 §10.15]` |

---

## 3. Layout e navegação

### 3.1 Janela

| Item | Valor |
| --- | --- |
| Tamanho mínimo | 960 × 640 (decisão); cai no breakpoint expanded `[M3 §8.1]` |
| Tamanho inicial | 1280 × 800, ou o último tamanho e posição salvos `[UX §10.2]` |
| Tema | Segue o sistema; opção claro, escuro ou sistema em Configurações `[UX §10.4]` |
| Barra de título | Decoração do sistema (GTK); o conteúdo começa abaixo dela |

### 3.2 Estrutura

```
┌───────────────┬──────────────────────────────────────────────────────┐
│ NavigationRail│ AppBar: título da página · "Atualizado há 3 min"     │
│ (extended,    │                         [refresh] [more_vert]        │
│  220dp)       ├──────────────────────────────────────────────────────┤
│               │ AlertBanner (só na Visão geral, quando houver alerta)│
│ Visão geral • │──────────────────────────────────────────────────────│
│ Diretórios    │                                                      │
│ Arquivos      │   Conteúdo: margens de 24dp, grid de 4/8dp           │
│  grandes      │                                                      │
│ Limpeza       │                                                      │
│ Docker        │                                                      │
│ Configurações │                                                      │
└───────────────┴──────────────────────────────────────────────────────┘
```

- **NavigationRail** à esquerda, `extended: true`, `minExtendedWidth: 220`, fundo `surface`, sem FAB, indicador ativo `secondaryContainer` com `corner-full` `[M3 §10.1]`. Seis destinos (dentro do limite de 3 a 7). O ícone selecionado usa `FILL 1`.
- **Badge** no destino Visão geral quando o disco está em atenção ou crítico: `Badge` com rótulo "!" em `warning`/`onWarning` ou `error`/`onError`, e rótulo semântico "Espaço em disco: atenção" ou "crítico" `[M3 §10.13]`. O badge persiste mesmo com o banner adiado.
- **AppBar** pequena por página: título em `titleLarge`, subtítulo com a hora da coleta (`bodySmall`, `onSurfaceVariant`) `[UX §2 heurística 1]`, ações `refresh` e `more_vert` (Configurações, Atalhos de teclado, Sobre), todas com tooltip `[M3 §10.2]` `[UX §10.2]`. `scrolledUnderElevation` padrão.
- **Conteúdo**: `CustomScrollView` com padding de 24dp, largura útil limitada a 1200dp.

### 3.3 Telas

| Destino | Conteúdo | Ação principal (único `FilledButton`) |
| --- | --- | --- |
| **Visão geral** | AlertBanner; card do disco principal com `numericHero`, estado e DiskUsageBar; card "Pode liberar X GB com segurança"; ConsumerBarList (5 a 7 itens + "Ver todos") `[UX §3 Miller]`; outros discos montados em cards menores | "Liberar 9,2 GB com segurança" (leva à revisão dos itens Seguros pré-selecionados e termina no CleanupConfirmDialog Seguro) |
| **Diretórios** | Lista de diretórios mapeados com tamanho, variação desde a última varredura e data; detalhe com ConsumerBarList dos filhos | "Adicionar diretório" |
| **Arquivos grandes** | Tabela própria sobre `ListView.builder` (nome, caminho, tamanho alinhado à direita, data de acesso), filtros por `FilterChip`, seleção múltipla `[M3 §10.5]` | "Mover para a lixeira" (habilitado com seleção) |
| **Limpeza** | `TabBar` com três abas: Lixeira, Caches, Builds; cada aba é uma lista de CleanupItemTile com CleanupSummaryBar fixa no rodapé | "Limpar 4,2 GB" / "Esvaziar lixeira" |
| **Docker** | Seções: Build cache, Containers parados, Imagens sem uso, Volumes sem uso; mesmo padrão de lista + barra de resumo | "Remover 7,3 GB" |
| **Configurações** | Limiares de alerta (`Slider` + campo numérico), pastas de busca de builds, tema, sobre | Sem botão principal: alterações valem na hora |

**Decisão (Limpeza):** abas (`TabBar` primária) em vez de `SegmentedButton`, porque cada categoria é uma vista com conteúdo e ações próprias, e cada aba mostra o total recuperável no rótulo ("Caches (4,2 GB)"). O segmented button fica para alternâncias dentro de uma vista, como a ordenação "Tamanho / Data / Nome" `[M3 §10.18]`.

### 3.4 Panes e larguras

- Até 1199dp de janela: um pane. Detalhe de diretório abre por navegação (lista → detalhe) com botão voltar na app bar.
- A partir de 1200dp (large): Diretórios vira list-detail com pane fixo de 412dp `[M3 §8.2]`; Arquivos grandes continua com pane único (a tabela precisa de largura).
- Com a janela mínima (960dp), o conteúdo tem 740dp (960 menos os 220 do rail), ou 692dp úteis com as margens. Toda tela deve funcionar nessa largura sem rolagem horizontal.

### 3.5 Atalhos de teclado

Base `[UX §10.3]`, sem usar Alt nem Super.

| Atalho | Ação |
| --- | --- |
| F5 ou Ctrl+R | Atualizar varredura |
| Ctrl+F | Filtrar a lista atual |
| Ctrl+A | Selecionar todos na lista atual |
| Ctrl+Z | Desfazer a última movimentação para a lixeira |
| Delete | Arquivos grandes: abre o CleanupConfirmDialog Perigoso com "Mover para a lixeira" marcado |
| Shift+Delete | Idem, com "Apagar permanentemente" marcado |
| Ctrl+1 a Ctrl+6 | Ir para o destino do rail |
| Ctrl+, | Configurações |
| Ctrl+? | Janela de atalhos |
| F10 | Menu principal (`more_vert`) |
| Esc | Fecha diálogo, menu ou banner focado; cancela seleção |
| Ctrl+Q | Sair |

---

## 4. Componentes

### 4.0 Componentes Material usados e como

| Componente | Uso no disk-cleanup | Regras |
| --- | --- | --- |
| `FilledButton` | Ação principal da tela; confirmação em diálogos | Um por tela `[M3 §10.6]`; rótulo com verbo e quantidade |
| `FilledButton` com `error` | Somente confirmação de exclusão permanente | Nunca fora de diálogo `[UX §6.3]` |
| `FilledButton.tonal` | Ação importante secundária ("Revisar limpeza" no card) | |
| `OutlinedButton` | "Cancelar varredura", "Copiar comando" | |
| `TextButton` | "Cancelar" em diálogos, ações de banner, "Ver todos" | |
| `IconButton` | Ações de app bar e de linha | Sempre com `tooltip` `[M3 §10.19]` |
| `Card.outlined` | Cards da Visão geral e grupos | `corner-medium`, sem rolar dentro `[M3 §10.3]` |
| `ListTile` / `CheckboxListTile` | Base do CleanupItemTile e listas | Densidade compacta |
| `TabBar` | Abas da Limpeza | |
| `FilterChip` | Filtros em Arquivos grandes | Sempre em grupo `[M3 §10.8]` |
| `SegmentedButton` | Ordenação; tema claro/escuro/sistema | Até 5 segmentos |
| `MenuAnchor` | Menu de contexto (clique direito, Shift+F10) em linhas | "Abrir no gerenciador de arquivos", "Copiar caminho", "Ignorar este diretório" `[M3 §10.14]` |
| `SnackBar` | Resultado de limpeza, Desfazer | Floating, largura 480dp, no máximo uma ação, sem ícone `[M3 §10.11]` |
| `MaterialBanner` | Base do AlertBanner | `[M3 §10.12]` |
| `AlertDialog` | Base do CleanupConfirmDialog | `[M3 §10.10]` |
| `LinearProgressIndicator` | Base do ScanProgress | `year2023: false` `[M3 §10.9]` |
| `Tooltip` | Bytes exatos, caminho completo, explicação de categoria | Nunca com informação que só exista ali `[UX §5.3]` |

Não usar: FAB (o app não tem ação construtiva dominante e FAB não serve para limpar `[M3 §10.6]`), `DataTable` (M2 e caro em listas longas `[M3 §10.5]`), navigation drawer, pizza, donut, gauge e qualquer 3D `[UX §5.1]`.

---

### 4.1 DiskUsageBar

Barra horizontal segmentada com o uso de um sistema de arquivos: usado, recuperável estimado e livre `[UX §5.2]`. Não é um progress indicator: tem semântica de medida, não de processo `[M3 §10.9]`.

**Anatomia**

```
 /home  ·  ext4                                     52,1 GB livres (20%)
 ┌──────────────────────────────┬─┬╱╱╱╱╱╱╱╱╱┬─┬─────────────────────────┐
 │ usado                        │ │ recuper.│ │ livre                   │
 └──────────────────────────────┴─┴╱╱╱╱╱╱╱╱╱┴─┴─────────────────────────┘
 ■ Usado 180,5 GB (71%)   ▨ Recuperável ~23,3 GB (9%)   □ Livre 52,1 GB (20%)
                                                         Total 256,0 GB
```

1. Cabeçalho opcional: ponto de montagem (`monoBody`) e sistema de arquivos (`bodySmall`); à direita, livre em valor e porcentagem.
2. Trilha: altura 16dp, `corner-extra-small`, cor `surfaceContainerHighest` (segmento livre), borda 1dp `outline`.
3. Segmento usado não recuperável: `primary` (ou `warning`/`error` conforme a severidade).
4. Segmento recuperável estimado: `tertiary` com listras diagonais de 45° em `tertiaryContainer` (4dp de período), posicionado à direita do usado, porque é parte do usado.
5. Separador de 2dp na cor do fundo entre segmentos.
6. Legenda: amostra (com o mesmo padrão), rótulo, valor e porcentagem, em `bodySmall` com tamanhos em `monoBodySmall`. A legenda é obrigatória: a barra sozinha não informa valores `[UX §5.3]`.

**Variantes**

| Variante | Diferença |
| --- | --- |
| `hero` | Na Visão geral, com cabeçalho, legenda completa e estado ("Espaço saudável" / "Pouco espaço" / "Espaço crítico") |
| `compact` | Cards de outros discos: sem legenda em linha; valores no texto ao lado ("31,0 GB livres de 500,1 GB") e na semântica |

**Estados**

| Estado | Visual |
| --- | --- |
| Normal | Usado em `primary`; texto de estado com `check_circle` em `success` |
| Atenção | Usado em `warning`; `warning` + "Pouco espaço" |
| Crítico | Usado em `error`; `error` + "Espaço crítico" |
| Sem estimativa de recuperável | Segmento recuperável ausente; legenda "Recuperável: calculando…" ou "não analisado" |
| Carregando (> 1 s) | Trilha vazia com borda e texto "Lendo o disco"; nada de skeleton antes de 1 s `[UX §8.1]` |
| Hover em segmento | Tooltip com bytes exatos ("180.512.334.848 bytes") |

**Flutter:** widget próprio `DiskUsageBar` com `CustomPaint` (ou `Row` de `Flexible` com `flex` proporcional e `DecoratedBox`), dentro de `Semantics(label: 'Disco /home: usado 180,5 GB, recuperável cerca de 23,3 GB, livre 52,1 GB de 256,0 GB, 20% livre')`. Segmentos com menos de 4dp de largura são desenhados com 4dp e o valor continua correto na legenda.

**Quando usar:** uso de um sistema de arquivos (Visão geral, cabeçalho de Diretórios). **Não usar:** para progresso de varredura ou limpeza (use ScanProgress), nem para comparar itens (use ConsumerBarList).

---

### 4.2 ConsumerBarList

Lista dos maiores consumidores de espaço com barras horizontais ordenadas e valor escrito `[UX §5.2]`.

**Anatomia (por linha)**

```
 [folder] node_modules (14 projetos)    ██████████████████░░░░░░   18,2 GB   7%
          ~/projetos/…                                             
```

1. Ícone da categoria (20dp, `onSurfaceVariant`).
2. Nome (`bodyMedium`) e, opcionalmente, caminho (`monoBodySmall`, `onSurfaceVariant`, truncado no meio).
3. Barra: 8dp de altura, `corner-extra-small`, cor `primary` sobre trilha `surfaceContainerHighest`; comprimento proporcional ao **maior item da lista** (o primeiro ocupa a largura toda), escala começando em zero.
4. Tamanho em `monoLabel`, alinhado à direita, com tooltip de bytes exatos.
5. Porcentagem do disco (`bodySmall`, `onSurfaceVariant`).
6. Rodapé: "Ver todos" (`TextButton`) quando houver mais itens.

**Variantes:** `overview` (5 a 7 itens, sem interação além de abrir o destino `[UX §3 Miller]`); `full` (todos os itens, ordenação por `SegmentedButton`, menu de contexto); `children` (filhos de um diretório mapeado, clique desce um nível).

**Estados:** normal; hover (state layer na linha toda); foco (anel na linha); carregando com resultados parciais (linhas entram em ordem conforme chegam, com reordenação animada em `standard`/300ms); item sem permissão (barra vazia, tamanho "Desconhecido" com `lock` e tooltip "Sem permissão de leitura").

**Flutter:** `ListView.builder` de `ConsumerBarTile` (base `ListTile` com `VisualDensity.compact`, barra num `LayoutBuilder`). Cada linha é focável e ativável por Enter. `Semantics` da linha: "node_modules, 14 projetos, 18,2 GB, 7% do disco".

**Quando usar:** comparação de tamanhos de itens do mesmo tipo. **Não usar:** para mostrar composição de um total (use DiskUsageBar) nem com mais de uma cor de barra por lista (cor não é categoria aqui).

---

### 4.3 AlertBanner

Alerta persistente de espaço em disco no topo da Visão geral `[M3 §10.12]` `[UX §7.1]`.

**Anatomia**

```
┌──────────────────────────────────────────────────────────────────────┐
│ [warning]  Pouco espaço em /home: 18,4 GB livres (7%). Dá para       │
│            liberar cerca de 9,2 GB com segurança.                    │
│                                         [Adiar]  [Revisar limpeza]   │
└──────────────────────────────────────────────────────────────────────┘
```

1. Ícone 24dp: `warning` ou `error`, na cor `onWarningContainer` / `onErrorContainer`.
2. Mensagem (`bodyLarge`): recurso, métrica (valor e porcentagem) e o que fazer `[UX §7.2]`.
3. Ações (`TextButton`, cor do "on" do container): "Adiar" à esquerda, ação principal à direita (mais perto da borda trailing).

**Variantes**

| Variante | Container / conteúdo | Ícone | Ações |
| --- | --- | --- | --- |
| Atenção | `warningContainer` / `onWarningContainer` | `warning` | "Adiar", "Revisar limpeza" |
| Crítico | `errorContainer` / `onErrorContainer` | `error` | "Adiar", "Revisar limpeza" |
| Informativo (Docker indisponível, dados desatualizados) | `surfaceContainerHigh` / `onSurface` | `info` | contextual |

**Estados:** visível; adiado (oculto por 24 h, o badge do rail continua); escalado (se o nível piora de atenção para crítico durante o adiamento, o banner volta na hora); resolvido (sai com animação de saída quando o disco volta ao normal com folga, ver [5.6](#56-alertas-de-espaço)).

**Flutter:** `MaterialBanner` inline (no topo do `CustomScrollView`, abaixo da app bar), não `ScaffoldMessenger.showMaterialBanner`, porque o banner pertence só à Visão geral. `backgroundColor`, `contentTextStyle` e `leading` vindos de `SeverityColors`/`ColorScheme`; `elevation: 0`. Anunciado uma vez ao aparecer (`SemanticsService.announce`, polite).

**Quando usar:** estado persistente de disco em atenção ou crítico, e estados persistentes do app (Docker indisponível). **Não usar:** para resultado de ação (SnackBar) nem para erro que bloqueia uma tarefa (diálogo ou PermissionState). Um banner por vez; se houver dois estados, mostra o de maior severidade.

---

### 4.4 RiskChip e indicador "requer root"

Rótulo de status, não interativo, com a classe de risco de um item `[UX §6.2]` `[UX §9.2]`. O "requer root" é um indicador separado, que pode aparecer junto com qualquer classe.

**Anatomia**

```
 ( ✓ Seguro )   ( ⚠ Atenção )   ( ⛔ Perigoso )      [admin_panel_settings] Requer admin
```

1. Container: altura 24dp, padding horizontal 8dp, `corner-small`, cor `*Container` da severidade.
2. Ícone 18dp (`check_circle`, `warning`, `dangerous`) na cor da severidade (`success`, `warning`, `error`).
3. Rótulo em `labelMedium`, cor `on*Container`.

| Classe | Container / rótulo | Ícone | Texto |
| --- | --- | --- | --- |
| Seguro | `successContainer` / `onSuccessContainer` | `check_circle` em `success` | "Seguro" |
| Atenção | `warningContainer` / `onWarningContainer` | `warning` em `warning` | "Atenção" |
| Perigoso | `errorContainer` / `onErrorContainer` | `dangerous` em `error` | "Perigoso" |

**Indicador "requer root" (`RootRequiredIndicator`):** sem container colorido (não é severidade), ícone `admin_panel_settings` 18dp em `onSurfaceVariant` + texto "Requer admin" em `labelMedium`; tooltip: "Requer permissão de administrador. O sistema vai pedir sua senha antes de apagar." Em espaço apertado, só o ícone, mantendo o tooltip e o rótulo semântico completo; o texto por extenso aparece de novo no CleanupConfirmDialog e na barra de resumo `[UX §8.5]`.

**Estados:** apenas repouso e hover (tooltip com a explicação da classe: "Seguro: é recriado automaticamente quando necessário."). Não recebe foco próprio: a linha que o contém é focável e a semântica da linha inclui o risco.

**Flutter:** widget próprio `RiskChip(level: RiskLevel.safe)` sobre `DecoratedBox` + `Row`, com `Semantics(label: 'Risco: seguro')` e `Tooltip`. Não usar `Chip`/`ActionChip`, que no M3 são interativos e "nunca aparecem sozinhos" `[M3 §10.8]`.

**Quando usar:** em toda linha apagável e no cabeçalho de categoria. **Não usar:** como filtro clicável (use `FilterChip` com o mesmo texto) nem para status do disco (use o texto de estado da DiskUsageBar).

---

### 4.5 CleanupItemTile

Linha de item apagável: checkbox, nome, contexto, tamanho, risco e root.

**Anatomia**

```
 [☑] [build]  node_modules                       ( ✓ Seguro ) [admin]   1,8 GB  [⋮]
              ~/projetos/loja-web · usado há 4 meses
```

1. Checkbox (alvo = linha inteira).
2. Ícone da categoria (20dp).
3. Título (`bodyMedium`): nome do item em termos do usuário ("Cache do npm", "node_modules", "postgres:15").
4. Subtítulo (`bodySmall`, `onSurfaceVariant`): caminho em `monoBodySmall` truncado no meio, e data de último uso ou modificação `[UX §2 heurística 6]`.
5. RiskChip e, se for o caso, RootRequiredIndicator.
6. Tamanho em `monoLabel`, alinhado à direita, tooltip com bytes exatos.
7. Menu de linha (`more_vert`, também por clique direito): "Abrir no gerenciador de arquivos", "Copiar caminho", "Ignorar este item".

**Variantes:** `single` (item único); `group` (cabeçalho de categoria com checkbox tristate, total e contagem: "Caches · 6 itens · 4,2 GB", expansível); `readOnly` (dentro do CleanupConfirmDialog, sem checkbox e sem menu).

**Estados**

| Estado | Visual |
| --- | --- |
| Não selecionado / selecionado | Checkbox; fundo inalterado |
| Hover, foco | State layer e anel de foco na linha |
| Desabilitado (em uso) | Conteúdo a 38%, subtítulo explica: "Em uso pelo Firefox. Feche o navegador para limpar." |
| Modificado recentemente | Não pré-selecionado; subtítulo em `warning` com ícone `schedule`: "Modificado há 2 dias" `[UX §2 heurística 5]` |
| Tamanho desconhecido | "Desconhecido" com `lock`; tooltip "Sem permissão de leitura" `[UX §8.5]` |
| Limpando | Checkbox desabilitado e texto "Limpando…" no lugar do tamanho; o progresso fica só na CleanupSummaryBar (um indicador por grupo `[M3 §10.9]`) |
| Limpo | Sai da lista com animação de saída (accelerate, 200ms) |
| Falhou | Ícone `error` + texto curto em `error` no subtítulo ("Permissão negada"); continua na lista |

**Flutter:** `CleanupItemTile` sobre `CheckboxListTile` (ou `ListTile` com `leading: Checkbox`) com `VisualDensity.compact`, `controlAffinity: ListTileControlAffinity.leading`. Grupo com `ExpansionTile` + `Checkbox(tristate: true)`. `Semantics` da linha: "node_modules, ~/projetos/loja-web, 1,8 GB, risco seguro, usado há 4 meses, selecionado".

**Quando usar:** listas de Limpeza e Docker. **Não usar:** em Arquivos grandes, que usa a tabela própria (mesmas regras de conteúdo, layout em colunas).

---

### 4.6 CleanupSummaryBar

Barra fixa no rodapé das listas de limpeza com o total selecionado e a ação. É o passo "revisar" `[UX §6.3]`; o botão dela sempre abre o [CleanupConfirmDialog](#47-cleanupconfirmdialog) na variante da classe de maior risco entre os itens selecionados.

```
─────────────────────────────────────────────────────────────────────────
 6 itens selecionados · 4,2 GB         [admin] 1 item pede senha   [Limpar 4,2 GB]
 Serão baixados de novo quando necessários.
```

- Fundo `surfaceContainer`, divisor superior `outlineVariant`, padding 16dp/24dp.
- Esquerda: contagem e total (`titleMedium`, total em algarismos tabulares); consequência em `bodySmall`.
- Direita: aviso de root quando houver; `FilledButton` com verbo e quantidade, que abre o CleanupConfirmDialog (nunca executa direto). Botão desabilitado sem seleção, com texto "Selecione itens para limpar".
- Durante a limpeza, a barra vira o ScanProgress de limpeza ("7,1 de 12,4 GB liberados", botão "Parar").

**Flutter:** `BottomAppBar` não é necessário; um `Material` com `color: surfaceContainer` no `bottomNavigationBar` do `Scaffold` da aba basta.

---

### 4.7 CleanupConfirmDialog

Diálogo de confirmação aberto antes de **toda** exclusão, em qualquer classe de risco (pedido do usuário). Diz o risco, o que some, quanto espaço volta e se o sistema vai pedir senha de administrador `[UX §6.1]` `[M3 §11.3]`. Na classe Seguro ele é leve: só resumo, sem lista obrigatória e sem passo extra.

**Anatomia**

```
┌──────────────────────────────────────────────────────┐
│                     [warning]                        │
│        Remover 5 imagens Docker (7,3 GB)?            │
│                                                      │
│ Imagens sem uso serão apagadas. Elas são baixadas    │
│ ou reconstruídas de novo quando um projeto precisar, │
│ o que pode levar tempo.                              │
│ ┌──────────────────────────────────────────────────┐ │
│ │ postgres:15            2,1 GB   criada há 3 meses│ │
│ │ node:20-alpine         1,4 GB   criada há 5 meses│ │
│ │ … e mais 3 imagens                               │ │
│ └──────────────────────────────────────────────────┘ │
│ [admin] 1 item exige senha de administrador. O       │
│ sistema vai pedir a senha a seguir.                  │
│                                                      │
│                  [Cancelar]  [Remover 5 imagens]     │
└──────────────────────────────────────────────────────┘
```

1. Ícone 24dp centralizado (`warning` em `warning`, ou `delete_forever` em `error`).
2. Headline (`headlineSmall`): ação + quantidade + tamanho, em forma de pergunta clara. Nunca "Tem certeza?" nem "Atenção!" `[M3 §11.3]`.
3. Texto (`bodyMedium`, `onSurfaceVariant`): consequência em linguagem do usuário.
4. Lista `readOnly` dos itens (nome, caminho ou tag em `monoBody`, tamanho, data), altura máxima de 240dp com rolagem; acima de 6 itens mostra "… e mais N" expansível `[UX §6.1]` `[UX §2 heurística 6]`.
5. Aviso de root, quando houver (ícone `admin_panel_settings` + texto).
6. Opção de modo (só Perigoso com lixeira disponível): grupo de rádio.
7. Ações: "Cancelar" (`TextButton`) à esquerda; confirmação (`FilledButton`) à direita, com texto descritivo.

**Variantes**

| Variante | Headline (exemplo) | Opção de modo | Botão de confirmação |
| --- | --- | --- | --- |
| Seguro (leve) | "Limpar 6 caches (4,2 GB)?" | Não | `FilledButton` (`primary`, nunca `error`): "Limpar 4,2 GB" |
| Atenção | "Remover 5 imagens Docker (7,3 GB)?" | Não | `FilledButton` (`primary`): "Remover 5 imagens" |
| Perigoso, com lixeira | "Apagar 12 arquivos (23,3 GB)?" | Sim: "Mover para a lixeira (recomendado)" marcado; "Apagar permanentemente" | Muda com a opção: `FilledButton` `primary` "Mover para a lixeira" ou `FilledButton` `error` "Apagar 23,3 GB" |
| Perigoso, sem lixeira (esvaziar lixeira, exclusão permanente forçada) | "Apagar permanentemente 214 itens da lixeira?" | Não | `FilledButton` `error`: "Apagar 3,8 GB" |

**Estados e comportamento**

- Variante Seguro: ícone `cleaning_services` em `primary`; corpo com o que some, quanto volta e "É recriado automaticamente quando necessário."; sem lista expandida obrigatória (os itens já foram revisados na CleanupSummaryBar; um "Ver itens" opcional pode expandir a lista `readOnly`); aviso de root quando houver. Confirmar executa na hora, sem outra etapa.
- Foco inicial em **Cancelar** em todas as variantes; Enter nunca dispara a ação destrutiva sem foco explícito nela; Esc cancela; ao fechar, o foco volta ao elemento que abriu `[UX §6.1]` `[M3 §11.3]`.
- "Cancelar" nunca fica desabilitado. A confirmação fica desabilitada enquanto a lista calcula o total.
- Ao confirmar: o diálogo fecha e o progresso aparece na CleanupSummaryBar. Se houver itens root, a UI mostra "Aguardando autorização do sistema" até o pkexec responder.
- Headline cabe em 4 linhas com texto a 200% `[M3 §11.3]`.

**Flutter:** `showDialog<CleanupDecision>` + `AlertDialog(icon:, title:, content:, actions:)`; largura máxima 560dp; `content` com `ConstrainedBox(maxHeight: 240)` + `ListView`. Opção de modo com `RadioListTile<DeleteMode>` (nas versões recentes do Flutter o par `groupValue`/`onChanged` está sendo substituído por `RadioGroup`; confira na 3.47). Foco inicial com `autofocus: true` no `TextButton` "Cancelar". `Semantics(scopesRoute: true, namesRoute: true)` com a headline como rótulo.

**Quando usar:** antes de executar qualquer exclusão, nas três classes (Seguro na variante leve). Com itens de classes diferentes no mesmo lote, vale a variante da classe mais alta. **Não usar:** para ações sem perda de dados (ignorar diretório, copiar caminho) nem para avisar de resultado.

---

### 4.8 ScanProgress

Progresso de varredura longa (e, na variante de limpeza, de exclusão em lote) com cancelamento `[UX §8.2]` `[M3 §10.9]`.

**Anatomia**

```
 Analisando /home                                      [Cancelar varredura]
 ████████████████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
 12,1 de 30,0 GB analisados · 18.430 arquivos · cerca de 2 minutos restantes
 ~/projetos/loja-web/node_modules/…/dist
```

1. Título (`titleMedium`): o que está sendo feito e onde.
2. `LinearProgressIndicator` 4dp, determinado sempre que houver total (o total da varredura é o espaço usado do sistema de arquivos, lido via `statvfs`).
3. Contadores (`bodySmall`, algarismos tabulares): unidades da tarefa e estimativa com "cerca de" `[UX §8.2]`.
4. Caminho atual (`monoBodySmall`, `onSurfaceVariant`, truncado no meio), atualizado no máximo 4 vezes por segundo.
5. Ação: `OutlinedButton` "Cancelar varredura" (ou "Parar limpeza"), sempre visível.

**Variantes:** `inline` (no topo do conteúdo da tela que está sendo varrida, com resultados parciais aparecendo abaixo `[UX §8.2]`); `summaryBar` (dentro da CleanupSummaryBar durante a limpeza: "7,1 de 12,4 GB liberados" `[UX §3 Gradiente]`); `appBar` (atualização em segundo plano de dados em cache: `LinearProgressIndicator` de 2dp sob a app bar, sem texto, com o subtítulo "Atualizando…").

**Estados**

| Estado | Comportamento |
| --- | --- |
| Menos de 1 s | Nada aparece `[UX §8.1]` |
| Contagem inicial | Indeterminado por no máximo alguns segundos, texto "Contando arquivos" |
| Em andamento | Determinado, com estimativa depois de 5 s de amostra |
| Estimativa estourada | Para em 100% com "Quase pronto" `[UX §8.2]` |
| Cancelando | Botão desabilitado com "Cancelando…"; resultados parciais permanecem, marcados "Varredura incompleta" |
| Concluído | Some; o subtítulo da app bar passa a "Atualizado agora" |
| Erro parcial | Contador extra "3 pastas sem permissão" com link "Ver detalhes" |

**Flutter:** `ScanProgress` com `LinearProgressIndicator(value: progress, year2023: false)` (ou `ProgressIndicatorThemeData(year2023: false)` no tema), `Semantics(liveRegion: true)` apenas no texto de estado, anunciando início, metade e fim, não cada atualização.

**Quando usar:** varreduras e limpezas que podem passar de 1 s. **Não usar:** um indicador por linha de lista (um indicador para o grupo `[M3 §10.9]`), nem para uso do disco (DiskUsageBar).

---

### 4.9 EmptyState

Página de placeholder quando não há conteúdo `[UX §8.3]`.

**Anatomia:** ícone 48dp em `onSurfaceVariant` (discreto); título em `headlineSmall` que comunica o estado; descrição opcional em `bodyMedium`, `onSurfaceVariant`, até 60 caracteres por linha; ação opcional (`FilledButton.tonal` ou `OutlinedButton`). Centralizado no pane, com 40dp de respiro acima.

| Situação | Ícone | Título | Descrição | Ação |
| --- | --- | --- | --- | --- |
| Nenhum diretório mapeado | `folder_special` | "Nenhum diretório mapeado" | "Adicione pastas para acompanhar o tamanho delas ao longo do tempo." | "Adicionar diretório" |
| Lixeira vazia | `delete` | "A lixeira está vazia" | "Não há nada para liberar aqui." | |
| Nenhum artefato de build | `build` | "Nenhum artefato de build encontrado" | "Procuramos em ~/projetos. Mude as pastas de busca nas configurações." | "Escolher pastas" |
| Caches limpos | `check_circle` | "Nenhum cache para limpar" | "Os caches conhecidos estão vazios ou abaixo de 1 MB." | |
| Docker não instalado | `deployed_code` | "Docker não encontrado" | "Instale o Docker para ver imagens e containers." | "Como instalar" (abre a documentação) |
| Filtro sem resultado | `search_off` | "Nenhum arquivo com esses filtros" | | "Limpar filtros" |

**Flutter:** `EmptyState(icon:, title:, description:, action:)` com `Center` + `ConstrainedBox(maxWidth: 480)` + `Column`. **Não usar** para erro ou falta de permissão (PermissionState), nem para carregamento.

---

### 4.10 PermissionState

Estado de falta de permissão, com causa e caminho para resolver `[UX §8.5]` `[UX §2 heurística 9]`.

**Anatomia:** mesma base do EmptyState, com ícone `lock` ou `admin_panel_settings`; explicação da causa; bloco de comando em `monoBody` sobre `surfaceContainerHighest`, `corner-medium`, com `IconButton` `content_copy` ("Copiar comando"); ações.

| Variante | Onde | Título | Texto e ação |
| --- | --- | --- | --- |
| Sem acesso ao Docker | Tela Docker (página inteira) | "Seu usuário não tem acesso ao Docker" | "Adicione seu usuário ao grupo docker e entre de novo na sessão." Comando: `sudo usermod -aG docker $USER`. Ações: "Copiar comando", "Usar senha de administrador" (pkexec) |
| Pasta sem leitura | Inline na linha ou no detalhe | "Sem permissão de leitura" | Tamanho como "Desconhecido", nunca 0 B. Ação: "Analisar com senha de administrador" |
| Autorização cancelada | Resultado (SnackBar) | | "Autorização cancelada. Os itens de administrador não foram apagados." |
| Autorização negada ou pkexec ausente | Diálogo de erro após a tentativa | "Não foi possível obter permissão de administrador" | "O polkit não respondeu ou não está instalado. Você pode rodar o comando abaixo no terminal." Comando equivalente para copiar |

**Flutter:** `PermissionState(kind:, command:, onElevate:)`; cópia via `Clipboard.setData` com SnackBar "Comando copiado.". **Não usar** para itens que só pedem senha na hora de apagar: esses mostram o RootRequiredIndicator e seguem o fluxo normal.

---

## 5. Padrões de interação

### 5.1 Classes de risco

**Decisão.** Toda exclusão abre o CleanupConfirmDialog (pedido do usuário); a classe define a variante do diálogo. O indicador "requer root" é independente da classe, e o diálogo avisa da senha em qualquer variante.

| Classe | Critério | Exemplos | Pré-seleção | Confirmação | Resultado |
| --- | --- | --- | --- | --- | --- |
| **Seguro** | Regenerável sem perda de estado | Caches (npm, uv, pip, yarn, gradle, navegadores), artefatos de build (`node_modules`, `.angular`, `target`, `.stack-work`, `dist-newstyle`, `build/`), build cache do Docker | Sim, exceto itens modificados nos últimos 14 dias ou em uso | Revisão na CleanupSummaryBar + CleanupConfirmDialog Seguro (leve: resumo, "Limpar X GB" e Cancelar) | SnackBar com o total liberado |
| **Atenção** | Perde estado recuperável com esforço | Imagens Docker sem uso, containers parados, volumes Docker sem uso, versões antigas de toolchains | Nunca | CleanupConfirmDialog Atenção listando itens | SnackBar com o total liberado |
| **Perigoso** | Arquivos pessoais ou perda permanente | Arquivos grandes, esvaziar a lixeira, qualquer exclusão permanente | Nunca | CleanupConfirmDialog Perigoso; "Mover para a lixeira" como padrão quando aplicável; botão destrutivo descritivo | SnackBar com "Desfazer" quando foi para a lixeira |

Volumes Docker podem guardar dados de bancos e de aplicações. Ficam em Atenção por decisão, mas o diálogo mostra para cada volume os containers que o usaram por último e o texto "Pode conter dados de aplicações, como bancos de dados." Nunca pré-selecionar imagens ou volumes em uso `[UX §6.2]`.

### 5.2 Selecionar → revisar → limpar

Fluxo único em todas as categorias `[UX §6.3]` `[UX §2 heurística 4]`.

1. **Selecionar.** A lista abre com a pré-seleção da classe. Checkbox de grupo tristate; Ctrl+A seleciona tudo.
2. **Revisar.** A CleanupSummaryBar mostra contagem, total estimado, consequência e aviso de root.
3. **Confirmar e limpar.** O botão da barra abre o CleanupConfirmDialog: na variante Seguro, só o resumo (o que some, quanto volta, "é recriado automaticamente") e "Limpar X GB"; em Atenção e Perigoso, a lista com nomes, tamanhos e datas. Um único pedido de pkexec por lote, cobrindo todos os itens root.
4. **Progresso.** ScanProgress na barra de resumo, acumulando o liberado; "Parar" interrompe depois do item atual.
5. **Resultado.** SnackBar com o total **efetivamente** liberado e o espaço livre agora: "12,4 GB liberados. Espaço livre agora: 64,5 GB (25%)." `[UX §3 Pico-fim]`. Se o liberado for menor que o estimado, a SnackBar ganha "Ver detalhes" com a explicação (arquivos em uso, camadas Docker compartilhadas) `[UX §6.3]`.

Atalho da Visão geral: "Liberar X GB com segurança" leva à revisão dos itens Seguros pré-selecionados de todas as categorias e termina no CleanupConfirmDialog Seguro; não pula nem a revisão nem o diálogo `[UX §2 heurística 7]`.

### 5.3 Desfazer

- Só existe Desfazer para o que foi para a lixeira. SnackBar: "12 itens movidos para a lixeira (3,4 GB)." com ação "Desfazer"; com ação, a SnackBar não some sozinha (padrão do Flutter) `[M3 §10.11]`. Ctrl+Z faz o mesmo enquanto a SnackBar estiver visível ou até a próxima ação destrutiva.
- Desfazer restaura pelos metadados da lixeira (`.trashinfo`, especificação freedesktop) e informa: "12 itens restaurados.".
- Itens Seguros e Atenção não têm Desfazer; o CleanupConfirmDialog e a barra de resumo dizem o custo de voltar atrás ("serão baixados de novo quando necessários").

### 5.4 Erros

Mensagem perto da origem, linguagem humana, causa e solução, sem culpar `[UX §8.4]`.

| Situação | Canal | Exemplo |
| --- | --- | --- |
| Falha parcial em lote | SnackBar com "Ver detalhes" (persistente por ter ação) + linhas marcadas com erro | "9,8 GB liberados. 3 itens não puderam ser apagados." |
| Detalhes da falha | Diálogo simples com lista: item, motivo e o que fazer | "Arquivo em uso pelo Firefox. Feche o navegador e tente de novo." |
| Falha que bloqueia a tela | Estado na própria tela (PermissionState ou AlertBanner informativo) | "Não foi possível ler /mnt/backup. O disco foi desmontado?" |
| Código técnico | Só como detalhe expansível ("Detalhes técnicos: EACCES, errno 13") | |

Erros importantes nunca aparecem só em SnackBar sem ação `[UX §7.1]`.

### 5.5 Sem permissão e pkexec

- O app roda como usuário comum. Itens fora do alcance do usuário mostram o RootRequiredIndicator desde a lista `[UX §8.5]`.
- Antes de pedir a senha, a UI sempre diz que vai pedir (barra de resumo e diálogo). A janela de senha é do polkit; o app mostra "Aguardando autorização do sistema" enquanto isso.
- Cancelou: nada root é apagado, os itens comuns seguem; resultado parcial na SnackBar.
- Negado ou polkit indisponível: PermissionState com o comando equivalente para copiar.
- Tamanho que não pôde ser lido aparece como "Desconhecido (sem permissão)" e fica fora dos totais, com nota "Total não inclui 2 pastas sem permissão".

### 5.6 Alertas de espaço

**Decisão:** limiares configuráveis; avaliação por sistema de arquivos; vale o primeiro critério atingido.

| Nível | Condição padrão | Exibição |
| --- | --- | --- |
| Normal | Livre ≥ 15% **e** ≥ 20 GB | Texto "Espaço saudável" com `check_circle` em `success` |
| Atenção | Livre < 15% **ou** < 20 GB | AlertBanner Atenção + badge `warning` no rail |
| Crítico | Livre < 5% **ou** < 5 GB | AlertBanner Crítico + badge `error` no rail |

- Crítico é avaliado antes de Atenção.
- Porcentagem e valor absoluto sempre juntos no texto `[UX §7.2]`.
- Histerese: para sair de um nível, o disco precisa passar o limiar com folga de 2 pontos percentuais **e** 2 GB, para o banner não piscar perto do limite `[UX §7.2]`.
- "Adiar" esconde o banner por 24 h por disco; piora de nível cancela o adiamento.
- Sem notificação do sistema e sem processo em segundo plano (**decisão**): o alerta só é avaliado com o app aberto.
- Configurações: `Slider` (0 a 50%, passos de 1) com campo numérico sincronizado para porcentagem e campo em GB, para Atenção e Crítico; validação "O limite crítico precisa ser menor que o de atenção." `[M3 §10.17]`.

### 5.7 Varredura longa e dados em cache

- Ao abrir, mostrar os dados da última varredura na hora, com "Atualizado há 3 h", e atualizar em segundo plano com a variante `appBar` do ScanProgress `[UX §3 Doherty]`.
- Varredura completa mostra resultados parciais, maiores primeiro, e pode ser cancelada a qualquer momento `[UX §8.2]`.
- Dados com mais de 24 h ganham AlertBanner informativo "Os dados são de ontem. Atualizar agora?" apenas se o usuário for limpar algo com base neles.

---

## 6. Conteúdo e microcopy

### 6.1 Tom

- Direto, calmo e concreto. Frases curtas, voz ativa, linguagem do usuário `[UX §10.5]`.
- Capitalização de frase em tudo: "Limpar cache do npm", não "Limpar Cache Do Npm" `[UX §4.2]`.
- Sem exclamação, sem "Atenção!", sem "Tem certeza?", sem desculpas `[M3 §11.3]`.
- Nunca culpar a pessoa: "Não foi possível ler a pasta" em vez de "Você não tem permissão".
- Nome técnico só com explicação: "Imagens Docker sem uso (dangling)" na primeira menção `[UX §2 heurística 2]`.

### 6.2 Vocabulário

| Termo | Quando |
| --- | --- |
| **Liberar** | Resultado em espaço: "Liberar 9,2 GB", "12,4 GB liberados" |
| **Limpar** | Caches e builds: "Limpar 4,2 GB" |
| **Mover para a lixeira** | Arquivos pessoais, reversível |
| **Apagar** | Exclusão permanente de arquivos: "Apagar 23,3 GB" |
| **Esvaziar a lixeira** | Nome da categoria e da headline |
| **Remover** | Objetos Docker (vocabulário do próprio Docker): "Remover 5 imagens" |
| **Recuperável** | Estimativa do que pode ser liberado; sempre com "cerca de" ou "~" na legenda |
| **Requer admin** | Rótulo curto do indicador root; por extenso "Requer permissão de administrador" |

Evitar "Excluir" (sinônimo de Apagar) para não ter dois verbos para a mesma ação.

### 6.3 Formatos

**Tamanhos (decisão: SI decimal, como o GNOME/Nautilus).**

| Regra | Exemplo |
| --- | --- |
| Base 1000: B, kB, MB, GB, TB (k minúsculo) | 1 GB = 1.000.000.000 bytes |
| Uma casa decimal a partir de kB, sempre com unidade | "23,3 GB", "512,0 MB", "1,0 kB" |
| Bytes sem decimal | "512 B" |
| Vírgula decimal e ponto de milhar (pt-BR) | "1.024,5 GB" só ocorre até virar "1,0 TB" |
| Espaço inseparável (U+00A0) entre número e unidade | "23,3 GB" não quebra linha |
| Arredondamento que vira 1000 sobe de unidade | 999.960 bytes → "1,0 MB", nunca "1.000,0 kB" |
| Bytes exatos no tooltip | "23.312.456.789 bytes" |
| Desconhecido | "Desconhecido" (nunca "0 B") |
| Estimativa | "cerca de 9,2 GB" no texto; "~9,2 GB" em legenda e chips |

**Outros números.**

| Tipo | Regra | Exemplo |
| --- | --- | --- |
| Contagem | Ponto de milhar | "18.430 arquivos" |
| Porcentagem | Inteira, sem espaço; abaixo de 1% uma casa | "7%", "0,4%" |
| Tamanho + porcentagem | Absoluto primeiro | "18,2 GB (7% do disco)" `[UX §5.3]` |
| Tempo restante | "cerca de" + unidade natural | "Cerca de 2 minutos restantes" |

**Datas.** Relativas até 7 dias ("agora", "há 3 min", "há 2 h", "ontem", "há 4 dias"); absolutas depois ("12 de mar. de 2026"); tooltip com data e hora completas ("12/03/2026 14:32"). Intervalos de uso: "usado há 4 meses".

**Caminhos.** `~` para a pasta pessoal; truncamento no meio; fonte mono; caminho completo no tooltip e em "Copiar caminho".

### 6.4 Exemplos

**Botões**

| Contexto | Texto |
| --- | --- |
| Ação principal da Visão geral | "Liberar 9,2 GB com segurança" |
| Limpeza de categoria Segura | "Limpar 4,2 GB" |
| Docker (Atenção) | "Remover 5 imagens" / "Remover 3 containers" |
| Perigoso com lixeira | "Mover para a lixeira" |
| Perigoso permanente | "Apagar 23,3 GB" |
| Esvaziar lixeira | "Apagar 3,8 GB" |
| Cancelar | "Cancelar" / "Cancelar varredura" / "Parar limpeza" |
| Sem seleção (desabilitado) | "Selecione itens para limpar" |

**Diálogos**

| Headline | Corpo |
| --- | --- |
| "Limpar 6 caches (4,2 GB)?" | "Os caches do npm, pip e navegadores serão apagados e 4,2 GB voltam ao disco. É recriado automaticamente quando necessário." |
| "Remover 3 containers parados (1,2 GB)?" | "Os containers e o que foi gravado dentro deles serão apagados. As imagens continuam disponíveis." |
| "Remover 2 volumes sem uso (5,4 GB)?" | "Pode conter dados de aplicações, como bancos de dados. Não dá para recuperar depois." |
| "Apagar 12 arquivos (23,3 GB)?" | "Mover para a lixeira permite restaurar depois. Apagar permanentemente libera o espaço agora e não dá para desfazer." |
| "Apagar permanentemente 214 itens da lixeira?" | "3,8 GB serão liberados. Não dá para desfazer." |

**SnackBars**

- "4,2 GB liberados. Espaço livre agora: 56,3 GB (22%)."
- "12 itens movidos para a lixeira (3,4 GB)." [Desfazer]
- "9,8 GB liberados. 3 itens não puderam ser apagados." [Ver detalhes]
- "Autorização cancelada. Os itens de administrador não foram apagados."
- "Comando copiado."

**Banners**

- Atenção: "Pouco espaço em /home: 18,4 GB livres (7%). Dá para liberar cerca de 9,2 GB com segurança." [Adiar] [Revisar limpeza]
- Crítico: "Espaço crítico em /: 3,1 GB livres (2%). Libere espaço para evitar falhas no sistema." [Adiar] [Revisar limpeza]

**Tooltips de categoria** `[UX §2 heurística 10]`

- Cache do pip: "Pacotes baixados pelo pip. São baixados de novo quando necessários."
- node_modules: "Dependências do projeto. Rode npm install para recriar."
- Build cache do Docker: "Camadas intermediárias de builds. O próximo build fica mais lento."

---

## 7. Acessibilidade

| Tema | Regra | Fonte |
| --- | --- | --- |
| Contraste de texto | ≥ 4,5:1 (3:1 para texto grande) nos dois temas; ver [2.3](#23-contraste-verificado) | `[UX §9.1]` |
| Contraste gráfico | ≥ 3:1 para bordas, segmentos e ícones de estado; onde o par falha, separador, padrão e rótulo | `[UX §9.1]` |
| Não depender de cor | Severidade e risco com ícone + texto + cor; gráfico com valores escritos | `[UX §9.2]` |
| Teclado | Todo fluxo funciona só com teclado; ordem de foco segue a leitura; setas dentro de listas e abas | `[UX §9.3]` `[M3 §12]` |
| Foco visível | Anel de 3dp, nunca removido, nunca coberto por SnackBar (SnackBar floating com margem acima do conteúdo focado) | `[UX §9.3]` |
| Foco em diálogo | Inicial em "Cancelar"; volta ao gatilho ao fechar | `[UX §6.1]` `[M3 §11.3]` |
| Alvos | 44 × 44dp de ponteiro; nunca abaixo de 24 × 24dp; 8dp entre alvos | `[M3 §12]` `[UX §9.3]` |
| Leitor de tela | `Semantics` com rótulo completo em DiskUsageBar, linhas de lista e RiskChip; tooltip em todo icon button; SnackBar anunciada sem mover foco | `[M3 §12]` |
| Live regions | Banner anunciado ao aparecer; varredura anuncia início, metade e fim | `[M3 §10.11]` |
| Texto a 200% | `MediaQuery.textScalerOf` respeitado; layouts testados com 200%; headline do diálogo cabe em 4 linhas | `[M3 §12]` |
| Movimento | Sem animação com `disableAnimations` / `prefers-reduced-motion` | Decisão |
| Equivalente de gráfico | Toda barra tem lista ou legenda navegável com os mesmos valores | `[UX §9.3]` |

Testes automatizados (widget tests de semântica e contraste) não substituem a validação visual e com leitor de tela feita por uma pessoa no app real `[UX §11]`.

---

## 8. Mapeamento para Flutter

### 8.1 Organização sugerida

```
lib/ui/theme/
  dc_theme.dart            buildDcTheme(Brightness)
  dc_color_schemes.dart    dcLightScheme, dcDarkScheme (gerados)
  severity_colors.dart     SeverityColors (ThemeExtension)
  dc_spacing.dart          DcSpacing (ThemeExtension)
  dc_text_styles.dart      DcTextStyles (ThemeExtension)
lib/ui/format/
  bytes.dart               formatBytes, formatBytesExact
  dates.dart               formatRelative
lib/ui/widgets/
  disk_usage_bar.dart  consumer_bar_list.dart  alert_banner.dart
  risk_chip.dart  root_required_indicator.dart  cleanup_item_tile.dart
  cleanup_summary_bar.dart  cleanup_confirm_dialog.dart  scan_progress.dart
  empty_state.dart  permission_state.dart
```

Enums de domínio usados pelos widgets: `RiskLevel { safe, caution, dangerous }`, `DiskSeverity { normal, warning, critical }`, `DeleteMode { trash, permanent }`.

### 8.2 ColorScheme

Constantes literais geradas (mesmos valores da tabela de 2.1). Um teste deve verificar que `ColorScheme.fromSeed(seedColor: Color(0xFF006A6A))` produz os mesmos valores; se divergir, regenere com o script do apêndice e atualize tabela, CSS e constantes juntos.

```dart
const dcLightScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFF006A6A),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFF9CF1F0),
  onPrimaryContainer: Color(0xFF004F4F),
  primaryFixed: Color(0xFF9CF1F0),
  primaryFixedDim: Color(0xFF80D5D4),
  onPrimaryFixed: Color(0xFF002020),
  onPrimaryFixedVariant: Color(0xFF004F4F),
  secondary: Color(0xFF4A6363),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFCCE8E7),
  onSecondaryContainer: Color(0xFF324B4B),
  secondaryFixed: Color(0xFFCCE8E7),
  secondaryFixedDim: Color(0xFFB0CCCB),
  onSecondaryFixed: Color(0xFF051F1F),
  onSecondaryFixedVariant: Color(0xFF324B4B),
  tertiary: Color(0xFF4B607C),
  onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: Color(0xFFD3E4FF),
  onTertiaryContainer: Color(0xFF334863),
  tertiaryFixed: Color(0xFFD3E4FF),
  tertiaryFixedDim: Color(0xFFB3C8E8),
  onTertiaryFixed: Color(0xFF041C35),
  onTertiaryFixedVariant: Color(0xFF334863),
  error: Color(0xFFBA1A1A),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFFDAD6),
  onErrorContainer: Color(0xFF93000A),
  surface: Color(0xFFF4FBFA),
  onSurface: Color(0xFF161D1D),
  surfaceDim: Color(0xFFD5DBDA),
  surfaceBright: Color(0xFFF4FBFA),
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFEFF5F4),
  surfaceContainer: Color(0xFFE9EFEE),
  surfaceContainerHigh: Color(0xFFE3E9E9),
  surfaceContainerHighest: Color(0xFFDDE4E3),
  onSurfaceVariant: Color(0xFF3F4948),
  outline: Color(0xFF6F7979),
  outlineVariant: Color(0xFFBEC9C8),
  inverseSurface: Color(0xFF2B3231),
  onInverseSurface: Color(0xFFECF2F1),
  inversePrimary: Color(0xFF80D5D4),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  surfaceTint: Color(0xFF006A6A),
);

const dcDarkScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFF80D5D4),
  onPrimary: Color(0xFF003737),
  primaryContainer: Color(0xFF004F4F),
  onPrimaryContainer: Color(0xFF9CF1F0),
  primaryFixed: Color(0xFF9CF1F0),
  primaryFixedDim: Color(0xFF80D5D4),
  onPrimaryFixed: Color(0xFF002020),
  onPrimaryFixedVariant: Color(0xFF004F4F),
  secondary: Color(0xFFB0CCCB),
  onSecondary: Color(0xFF1B3534),
  secondaryContainer: Color(0xFF324B4B),
  onSecondaryContainer: Color(0xFFCCE8E7),
  secondaryFixed: Color(0xFFCCE8E7),
  secondaryFixedDim: Color(0xFFB0CCCB),
  onSecondaryFixed: Color(0xFF051F1F),
  onSecondaryFixedVariant: Color(0xFF324B4B),
  tertiary: Color(0xFFB3C8E8),
  onTertiary: Color(0xFF1C314B),
  tertiaryContainer: Color(0xFF334863),
  onTertiaryContainer: Color(0xFFD3E4FF),
  tertiaryFixed: Color(0xFFD3E4FF),
  tertiaryFixedDim: Color(0xFFB3C8E8),
  onTertiaryFixed: Color(0xFF041C35),
  onTertiaryFixedVariant: Color(0xFF334863),
  error: Color(0xFFFFB4AB),
  onError: Color(0xFF690005),
  errorContainer: Color(0xFF93000A),
  onErrorContainer: Color(0xFFFFDAD6),
  surface: Color(0xFF0E1514),
  onSurface: Color(0xFFDDE4E3),
  surfaceDim: Color(0xFF0E1514),
  surfaceBright: Color(0xFF343A3A),
  surfaceContainerLowest: Color(0xFF090F0F),
  surfaceContainerLow: Color(0xFF161D1D),
  surfaceContainer: Color(0xFF1A2121),
  surfaceContainerHigh: Color(0xFF252B2B),
  surfaceContainerHighest: Color(0xFF2F3636),
  onSurfaceVariant: Color(0xFFBEC9C8),
  outline: Color(0xFF889392),
  outlineVariant: Color(0xFF3F4948),
  inverseSurface: Color(0xFFDDE4E3),
  onInverseSurface: Color(0xFF2B3231),
  inversePrimary: Color(0xFF006A6A),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  surfaceTint: Color(0xFF80D5D4),
);
```

### 8.3 ThemeExtension de severidade

```dart
@immutable
class SeverityColors extends ThemeExtension<SeverityColors> {
  const SeverityColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
  });

  final Color success, onSuccess, successContainer, onSuccessContainer;
  final Color warning, onWarning, warningContainer, onWarningContainer;

  static const light = SeverityColors(
    success: Color(0xFF006D43),
    onSuccess: Color(0xFFFFFFFF),
    successContainer: Color(0xFF92F7BC),
    onSuccessContainer: Color(0xFF005231),
    warning: Color(0xFF775A00),
    onWarning: Color(0xFFFFFFFF),
    warningContainer: Color(0xFFFFDF99),
    onWarningContainer: Color(0xFF5A4300),
  );

  static const dark = SeverityColors(
    success: Color(0xFF76DAA1),
    onSuccess: Color(0xFF003920),
    successContainer: Color(0xFF005231),
    onSuccessContainer: Color(0xFF92F7BC),
    warning: Color(0xFFF4BF2A),
    onWarning: Color(0xFF3F2E00),
    warningContainer: Color(0xFF5A4300),
    onWarningContainer: Color(0xFFFFDF99),
  );

  SeverityTone forRisk(RiskLevel level, ColorScheme scheme) => switch (level) {
        RiskLevel.safe => SeverityTone(success, onSuccess, successContainer, onSuccessContainer),
        RiskLevel.caution => SeverityTone(warning, onWarning, warningContainer, onWarningContainer),
        RiskLevel.dangerous => SeverityTone(
            scheme.error, scheme.onError, scheme.errorContainer, scheme.onErrorContainer),
      };

  SeverityTone forDisk(DiskSeverity severity, ColorScheme scheme) => switch (severity) {
        DiskSeverity.normal => SeverityTone(success, onSuccess, successContainer, onSuccessContainer),
        DiskSeverity.warning => SeverityTone(warning, onWarning, warningContainer, onWarningContainer),
        DiskSeverity.critical => SeverityTone(
            scheme.error, scheme.onError, scheme.errorContainer, scheme.onErrorContainer),
      };

  @override
  SeverityColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
  }) =>
      SeverityColors(
        success: success ?? this.success,
        onSuccess: onSuccess ?? this.onSuccess,
        successContainer: successContainer ?? this.successContainer,
        onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
        warning: warning ?? this.warning,
        onWarning: onWarning ?? this.onWarning,
        warningContainer: warningContainer ?? this.warningContainer,
        onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      );

  @override
  SeverityColors lerp(SeverityColors? other, double t) {
    if (other == null) return this;
    return SeverityColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer: Color.lerp(successContainer, other.successContainer, t)!,
      onSuccessContainer: Color.lerp(onSuccessContainer, other.onSuccessContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      warningContainer: Color.lerp(warningContainer, other.warningContainer, t)!,
      onWarningContainer: Color.lerp(onWarningContainer, other.onWarningContainer, t)!,
    );
  }
}

@immutable
class SeverityTone {
  const SeverityTone(this.color, this.onColor, this.container, this.onContainer);
  final Color color, onColor, container, onContainer;
}
```

Leitura: `Theme.of(context).extension<SeverityColors>()!` `[M3 §14.2]`.

### 8.4 Espaçamento e estilos de texto

```dart
@immutable
class DcSpacing extends ThemeExtension<DcSpacing> {
  const DcSpacing();

  final double space1 = 4, space2 = 8, space3 = 12, space4 = 16, space5 = 20;
  final double space6 = 24, space8 = 32, space10 = 40, space12 = 48, space16 = 64;
  final double pageMargin = 24, gutter = 24, contentMaxWidth = 1200;
  final double railExtendedWidth = 220, tableRowHeight = 44, pointerTargetMin = 44;
  final double diskBarHeight = 16, diskBarGap = 2, consumerBarHeight = 8;

  @override
  DcSpacing copyWith() => this;

  @override
  DcSpacing lerp(DcSpacing? other, double t) => this;
}

@immutable
class DcTextStyles extends ThemeExtension<DcTextStyles> {
  const DcTextStyles({
    required this.numericHero,
    required this.monoBody,
    required this.monoBodySmall,
    required this.monoLabel,
  });

  final TextStyle numericHero, monoBody, monoBodySmall, monoLabel;

  factory DcTextStyles.from(TextTheme t) {
    const tabular = [FontFeature.tabularFigures()];
    TextStyle mono(TextStyle s) =>
        s.copyWith(fontFamily: 'RobotoMono', letterSpacing: 0, fontFeatures: tabular);
    return DcTextStyles(
      numericHero: t.displaySmall!.copyWith(fontFeatures: tabular),
      monoBody: mono(t.bodyMedium!),
      monoBodySmall: mono(t.bodySmall!),
      monoLabel: mono(t.labelLarge!),
    );
  }

  @override
  DcTextStyles copyWith({
    TextStyle? numericHero,
    TextStyle? monoBody,
    TextStyle? monoBodySmall,
    TextStyle? monoLabel,
  }) =>
      DcTextStyles(
        numericHero: numericHero ?? this.numericHero,
        monoBody: monoBody ?? this.monoBody,
        monoBodySmall: monoBodySmall ?? this.monoBodySmall,
        monoLabel: monoLabel ?? this.monoLabel,
      );

  @override
  DcTextStyles lerp(DcTextStyles? other, double t) {
    if (other == null) return this;
    return DcTextStyles(
      numericHero: TextStyle.lerp(numericHero, other.numericHero, t)!,
      monoBody: TextStyle.lerp(monoBody, other.monoBody, t)!,
      monoBodySmall: TextStyle.lerp(monoBodySmall, other.monoBodySmall, t)!,
      monoLabel: TextStyle.lerp(monoLabel, other.monoLabel, t)!,
    );
  }
}
```

Fontes no `pubspec.yaml`: famílias `Roboto` (400, 500, 700) e `RobotoMono` (400, 500) como assets.

### 8.5 ThemeData

```dart
ThemeData buildDcTheme(Brightness brightness) {
  final scheme = brightness == Brightness.light ? dcLightScheme : dcDarkScheme;
  final base = ThemeData(
    colorScheme: scheme,
    fontFamily: 'Roboto',
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
  );

  return base.copyWith(
    extensions: [
      brightness == Brightness.light ? SeverityColors.light : SeverityColors.dark,
      const DcSpacing(),
      DcTextStyles.from(base.textTheme),
    ],
    listTileTheme: const ListTileThemeData(
      visualDensity: VisualDensity.compact,
      contentPadding: EdgeInsetsDirectional.symmetric(horizontal: 16),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      width: 480,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.secondaryContainer,
      minExtendedWidth: 220,
    ),
    tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 500)),
    progressIndicatorTheme: const ProgressIndicatorThemeData(year2023: false),
    sliderTheme: const SliderThemeData(year2023: false),
  );
}

MaterialApp(
  theme: buildDcTheme(Brightness.light),
  darkTheme: buildDcTheme(Brightness.dark),
  themeMode: settings.themeMode,
);
```

`useMaterial3` já é `true` por padrão `[M3 §2.2]`. Confira na 3.47 os nomes `CardThemeData`/`DialogThemeData` e os parâmetros `year2023` e `minExtendedWidth` do tema, marcados como não confirmados na pesquisa `[M3 §14.2]` `[M3 §10.9]`.

### 8.6 Correspondência de tokens

| Token CSS | Flutter |
| --- | --- |
| `--md-sys-color-*` | `ColorScheme.*` (`inverse-on-surface` → `onInverseSurface`) |
| `--dc-color-success*`, `--dc-color-warning*` | `SeverityColors` |
| `--dc-color-critical*` | `ColorScheme.error*` |
| `--md-sys-typescale-*` | `TextTheme.*` (`height` = line-height / size) |
| `--dc-typescale-mono-*`, `--dc-font-feature-numeric` | `DcTextStyles` |
| `--md-sys-shape-corner-*` | `BorderRadius.circular(n)` nos temas de componente |
| `--md-sys-elevation-level*` | `elevation:` em dp |
| `--md-sys-motion-duration-*` | `Durations.short1` … `Durations.extralong4` |
| `--md-sys-motion-easing-*` | `Easing.*`, `Curves.easeInOutCubicEmphasized` |
| `--md-sys-state-*` | constantes em `WidgetStateProperty.resolveWith` `[M3 §9.3]` |
| `--dc-space-*`, `--dc-*` de layout | `DcSpacing` |

### 8.7 Formatação de bytes

```dart
const _units = ['B', 'kB', 'MB', 'GB', 'TB', 'PB'];
const _nbsp = ' ';

String formatBytes(int bytes) {
  if (bytes < 1000) return '$bytes${_nbsp}B';
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 999.95 && unit < _units.length - 1) {
    value /= 1000;
    unit++;
  }
  return '${NumberFormat('#,##0.0', 'pt_BR').format(value)}$_nbsp${_units[unit]}';
}

String formatBytesExact(int bytes) => '${NumberFormat('#,##0', 'pt_BR').format(bytes)} bytes';
```

O limiar 999,95 faz o arredondamento subir de unidade em vez de mostrar "1.000,0 kB".

---

## 9. Checklist de revisão

Usar antes de entregar cada tela. A validação visual e de comportamento no app real é feita por uma pessoa `[UX §11]`.

**Tokens e tema**

- [ ] Nenhum hex fora de `dc_color_schemes.dart`, `severity_colors.dart` e `tokens.css`.
- [ ] Constantes de cor batem com `ColorScheme.fromSeed(0xFF006A6A)` (teste) e com o CSS.
- [ ] Containers sempre com o "on" correspondente.
- [ ] Um único `FilledButton` por tela; `error` só no botão de exclusão permanente.
- [ ] Cards e barras sem `corner-large` ou `corner-full`.

**Visão geral e dados**

- [ ] Espaço livre é o primeiro elemento percebido; estado do disco com ícone + texto + cor.
- [ ] A tela mostra quando os dados foram coletados.
- [ ] Barras ordenadas com valor escrito; nenhuma pizza, donut, gauge ou 3D.
- [ ] DiskUsageBar com separadores, listras no recuperável, borda `outline` e legenda com valores.
- [ ] Todos os tamanhos em SI, uma casa decimal, unidade, vírgula decimal, tooltip com bytes exatos.
- [ ] Top consumidores com 5 a 7 itens e "Ver todos".

**Limpeza**

- [ ] Toda linha apagável tem RiskChip; itens root têm o indicador e o aviso antes da senha.
- [ ] Pré-seleção só de itens Seguros, fora os modificados recentemente ou em uso.
- [ ] Toda exclusão passa pela CleanupSummaryBar e abre o CleanupConfirmDialog: Seguro na variante leve (resumo, "Limpar X GB" sem estilo destrutivo), Atenção e Perigoso com lista de itens.
- [ ] Diálogo com headline específica, lista de itens, total e botão descritivo; foco inicial em Cancelar; Esc cancela.
- [ ] Perigoso com lixeira disponível traz "Mover para a lixeira" marcado.
- [ ] Resultado mostra o espaço efetivamente liberado e as falhas; Desfazer quando foi para a lixeira.

**Alertas e estados**

- [ ] Limiares padrão 15%/20 GB e 5%/5 GB, configuráveis, com histerese e "Adiar".
- [ ] Banner só na Visão geral; badge no rail; nenhuma notificação do sistema.
- [ ] Varredura com barra determinada, unidades, "cerca de", resultados parciais e Cancelar sempre visível.
- [ ] Nada de indicador em carga abaixo de 1 s.
- [ ] Toda tela tem EmptyState; falta de permissão usa PermissionState; tamanho ilegível nunca aparece como 0 B.

**Acessibilidade**

- [ ] Contraste conferido nos dois temas para qualquer cor nova.
- [ ] Todo fluxo funciona só com teclado; foco visível e nunca coberto.
- [ ] Alvos de ponteiro ≥ 44dp; nada abaixo de 24dp.
- [ ] Semântica completa em barras, linhas e chips; icon buttons com tooltip.
- [ ] Layout testado com texto a 200% e com animações desligadas.

**Desktop Linux**

- [ ] Janela mínima 960 × 640 sem rolagem horizontal; tamanho e posição lembrados.
- [ ] Atalhos da [seção 3.5](#35-atalhos-de-teclado) funcionam.
- [ ] Tema segue o sistema, com opção claro, escuro ou sistema.
- [ ] Textos com capitalização de frase e o vocabulário da [seção 6.2](#62-vocabulário).

---

## 10. Divergências entre decisões e pesquisa

As decisões do projeto prevalecem; esta tabela registra onde a pesquisa recomendava outra coisa.

| Tema | Pesquisa | Decisão aplicada |
| --- | --- | --- |
| Notificação do sistema | Notificar no nível crítico e ao fim de varredura longa com a janela fora de foco `[UX §7.1]` `[UX §7.2]` `[UX §8.2]` | Sem notificação do sistema e sem daemon; alerta só dentro do app |
| Arquivos pessoais | Mover para a lixeira direto, sem diálogo, com Desfazer; preferir desfazer a confirmar `[UX §6.1]` `[UX §6.2]` | Continua Perigoso: CleanupConfirmDialog com "Mover para a lixeira" como padrão, e Desfazer depois |
| Artefatos de build | Diálogo de confirmação listando projetos `[UX §6.2]` | Continua Seguro, com o CleanupConfirmDialog leve (resumo, sem lista obrigatória); mantida a regra de não pré-selecionar projetos recentes |
| Build cache do Docker | Confirmação específica `[UX §6.2]` | Continua Seguro, com o CleanupConfirmDialog leve mostrando o tamanho recuperável |
| Volumes Docker | Não cobertos pela matriz; Docker tratado como risco alto `[UX §1]` | Atenção, com aviso de dados de aplicações e sem pré-seleção |
| "Toda exclusão abre um diálogo informando riscos e pedindo senha root quando necessário" (pedido do usuário) | A pesquisa prefere desfazer a confirmar e evita confirmação em ações rotineiras `[UX §6.1]` | Segue o usuário: toda exclusão abre o CleanupConfirmDialog; a classe Seguro usa a variante leve para não acrescentar passo |
| Rail | Recolhido em medium e expanded, expandido de large em diante `[M3 §10.1]` | Sempre expandido (a janela mínima já é expanded); largura de 220dp para caber em 960dp |
| Navegação | Header bar com alternador de vistas, no estilo GNOME `[UX §10.2]` | NavigationRail do M3 com app bar por página |
| Densidade | Usuário deve optar por densidade alta; alvos de 48dp `[M3 §8.3]` `[M3 §12]` | `VisualDensity.compact` fixo em listas e tabelas; alvo mínimo de ponteiro 44dp |
| Ícone de permissão | Cadeado + texto `[UX §8.5]` | `admin_panel_settings` para "requer root"; `lock` só para "sem permissão de leitura" |
| Unidades | Escolher GB ou GiB; a pesquisa de M3 sugere alternância GB/GiB `[UX §2]` `[M3 §10.18]` | Só SI decimal, sem alternância |
| Treemap | Modo opcional de exploração em diretórios `[UX §5.2]` | Fora do escopo; só barras |
| Banner crítico | Fora do M3 atual; Flutter mantém `MaterialBanner` `[M3 §10.12]` | Mantido como base do AlertBanner |

---

## 11. Apêndice: geração das cores

Script usado para gerar todos os hex deste documento e de `tokens.css`. Requer Node 22 e `npm install @material/material-color-utilities@0.4.0`. O pacote 0.4.0 publica imports ESM sem extensão; rode com um loader que acrescente `.js` (por exemplo, um hook `resolve` registrado com `node --import`).

```js
import {
  Hct, SchemeTonalSpot, MaterialDynamicColors, Blend, TonalPalette,
  argbFromHex, hexFromArgb,
} from '@material/material-color-utilities';

const SEED = '#006A6A';
const seed = Hct.fromInt(argbFromHex(SEED));
const mdc = new MaterialDynamicColors();

for (const isDark of [false, true]) {
  const scheme = new SchemeTonalSpot(seed, isDark, 0.0, '2021');
  for (const role of ['primary', 'onPrimary', 'primaryContainer' /* , ...todos os papéis */]) {
    console.log(isDark ? 'dark' : 'light', role, hexFromArgb(mdc[role]().getArgb(scheme)));
  }
}

function customColor(sourceHex) {
  const harmonized = Hct.fromInt(Blend.harmonize(argbFromHex(sourceHex), argbFromHex(SEED)));
  const palette = TonalPalette.fromHueAndChroma(harmonized.hue, Math.max(48, harmonized.chroma));
  const tone = (t) => hexFromArgb(palette.tone(t));
  return {
    light: { color: tone(40), onColor: tone(100), container: tone(90), onContainer: tone(30) },
    dark: { color: tone(80), onColor: tone(20), container: tone(30), onContainer: tone(90) },
  };
}

console.log('success', customColor('#2E7D32'));
console.log('warning', customColor('#F9A825'));
```

Contraste: razão WCAG `(L1 + 0,05) / (L2 + 0,05)` sobre a luminância relativa de cada hex. Qualquer cor nova entra na tabela da [seção 2.3](#23-contraste-verificado) antes de ser usada.
