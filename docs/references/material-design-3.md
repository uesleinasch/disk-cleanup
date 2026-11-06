# Material Design 3: referência para o disk-cleanup

Documento de referência sobre o Material Design 3 (M3, também chamado de Material You) para o projeto **disk-cleanup**, gerenciador de espaço em disco para desktop Linux distribuído como AppImage.

**Stack decidida:** Flutter (desktop Linux, Flutter 3.47 stable, Material 3 nativo). Cada seção traz primeiro a especificação do Material (agnóstica de plataforma) e, em seguida, o equivalente em Flutter. Os tokens CSS (`--md-sys-*`) continuam documentados porque o protótipo será feito em HTML.

Data da pesquisa: 2026-11-06. Os valores numéricos vêm de arquivos de tokens oficiais (material-web, gerados a partir da fonte de tokens do Google, versão "Google Material 3 34.0.21"), do código-fonte do Flutter e das páginas do m3.material.io. Quando um valor não pôde ser confirmado numa fonte, ele aparece marcado como **(não confirmado)**.

---

## Sumário

1. [Contexto: M3, M3 Expressive e o que o Flutter implementa](#1-contexto-m3-m3-expressive-e-o-que-o-flutter-implementa)
2. [Princípios do M3 e o que mudou do M2](#2-princípios-do-m3-e-o-que-mudou-do-m2)
3. [Sistema de cores](#3-sistema-de-cores)
4. [Tipografia](#4-tipografia)
5. [Shape (forma)](#5-shape-forma)
6. [Elevation](#6-elevation)
7. [Motion](#7-motion)
8. [Layout](#8-layout)
9. [State layers e estados](#9-state-layers-e-estados)
10. [Componentes](#10-componentes)
11. [Ações destrutivas, confirmação e feedback](#11-ações-destrutivas-confirmação-e-feedback)
12. [Acessibilidade](#12-acessibilidade)
13. [Material Symbols (ícones)](#13-material-symbols-ícones)
14. [Mapeamento de tokens para Flutter (ThemeData e ThemeExtension)](#14-mapeamento-de-tokens-para-flutter-themedata-e-themeextension)
15. [Tabela final de tokens de referência (CSS)](#15-tabela-final-de-tokens-de-referência-css)
16. [Fontes](#16-fontes)

---

## 1. Contexto: M3, M3 Expressive e o que o Flutter implementa

- Em maio de 2025 o Google publicou a atualização **M3 Expressive**: física de motion com springs, 35 novas formas com shape morphing, novos raios de canto (`large-increased` 20dp, `extra-large-increased` 32dp, `extra-extra-large` 48dp), 15 estilos tipográficos "emphasized", novos componentes (button groups, split button, FAB menu, loading indicator, toolbars) e a descontinuação de alguns componentes (navigation drawer, segmented button, small FAB, top app bars "medium" e "large" baseline).
- A página oficial do Flutter no m3.material.io afirma literalmente: **"Flutter supports original M3 components. M3 Expressive is not available on Flutter."**
- Consequência prática para o disk-cleanup: o app usa o **M3 original (baseline)**. Componentes que o Expressive marca como "não recomendados" (navigation drawer, segmented button) continuam válidos no Flutter, porque os substitutos (expanded navigation rail no sentido Expressive, connected button group) não existem como widgets do Flutter. Este documento sinaliza onde há divergência.
- O material-web (`@material/web`) está em modo de manutenção ("MWC is in maintenance mode pending new maintainers", segundo o README do repositório). Para o protótipo HTML, use os **tokens CSS** deste documento; não é necessário adotar a biblioteca de componentes.

---

## 2. Princípios do M3 e o que mudou do M2

### 2.1 Pilares que atravessam a documentação

- **Personalização por cor dinâmica:** um esquema de cores inteiro é gerado a partir de uma única source color (papel de parede do usuário ou conteúdo do app).
- **Acessibilidade embutida no sistema:** os algoritmos de cor usam o eixo *tone* para garantir pares de contraste (por exemplo, 3:1 entre container e rótulo de botão). Papéis de cor ("on-*") garantem legibilidade em qualquer nível de contraste.
- **Adaptação por breakpoints:** layouts mudam de 1 para 2 ou 3 panes conforme a largura da janela, não conforme o tipo de dispositivo.
- **Expressividade controlada por tokens:** cor, tipografia, forma, elevação e motion são definidos por design tokens (`md.sys.*`), o que permite trocar o tema sem mexer nos componentes.

### 2.2 Mudanças do M2 para o M3

| Área | M2 | M3 | Fonte |
|---|---|---|---|
| Cor | Paleta fixa com primary/secondary e variantes | Esquema gerado de uma source color, 5 tonal palettes, dezenas de color roles, light/dark derivados juntos | m3 color/system |
| Superfícies | Overlays de elevação (+1 a +5) sobre `surface` | Desde fev/2023, papéis `surface-container-*` baseados em tone, desacoplados da elevação | m3 color/system |
| Elevation | Sombras em todos os níveis | Cor tonal no lugar de sombra; sombra só quando necessária; 6 níveis (0 a 5); `surface-tint` descontinuado | m3 elevation |
| Tipografia | h1 a h6, subtitle, body, caption, button, overline | 5 papéis (display, headline, title, body, label) x 3 tamanhos = 15 estilos | m3 typography |
| Shape | Cantos pequenos | Escala de 10 passos; botões totalmente arredondados (`full`); dialogs com raio maior | m3 shape, buttons, dialogs |
| Botões | Ícone e rótulo com cores independentes; botão de texto neutro | Ícone e rótulo compartilham a cor; ícones de 20dp; formato totalmente arredondado; "neutral text button" não é mais recomendado | m3 buttons |
| Motion | Easing utilitário, durações curtas | Easing mais expressivo (saída rápida, chegada suave), durações um pouco maiores | m3 easing-and-duration |
| Dialogs | Cantos pequenos, título discreto | Raio maior, mais padding, headline maior e mais escuro | m3 dialogs |
| Snackbar | Apenas temporária | Pode ser temporária (dismissive) ou persistir até uma ação (non-dismissive) | m3 snackbar |

Equivalência de nomes do `TextTheme` no Flutter (M2 para M3): `headline1`→`displayLarge`, `headline2`→`displayMedium`, `headline3`→`displaySmall`, `headline4`→`headlineMedium`, `headline5`→`headlineSmall`, `headline6`→`titleLarge`, `subtitle1`→`titleMedium`, `subtitle2`→`titleSmall`, `bodyText1`→`bodyLarge`, `bodyText2`→`bodyMedium`, `caption`→`bodySmall`, `button`→`labelLarge`, `overline`→`labelSmall` **(não confirmado nesta pesquisa; relevante apenas para portar código antigo)**.

**Flutter:** `ThemeData.useMaterial3` é `true` por padrão ("This flag is true by default"). Não é preciso ligá-lo; basta não desligar.

---

## 3. Sistema de cores

### 3.1 Como o sistema funciona

Fluxo oficial (m3.material.io, "How the system works"):

1. **Source color:** uma única cor de origem (papel de parede, conteúdo do app ou cor da marca).
2. **Key colors:** os algoritmos manipulam hue e chroma da source color para gerar 5 key colors: **primary, secondary, tertiary, neutral, neutral variant**. A paleta de **error** é fixa.
3. **Tonal palettes:** cada key color vira uma paleta tonal com tons de 0 a 100 em passos de 10, mais 95, 98 e 99 (13 tons). Algumas paletas têm tons extras (a neutral tem 4, 6, 12, 17, 22, 24, 87, 92, 94, 96).
4. **Color roles:** tons específicos de cada paleta são atribuídos aos papéis de cor, em light e dark. Exemplo: `primary` = primary40 no light; `on-primary` = primary100.
5. **UI:** componentes usam papéis, nunca hex. Os papéis permanecem os mesmos quando a source color muda.

O espaço de cor usado é o **HCT** (hue, chroma, tone), baseado em CAM16 e L* (material-color-utilities). *Tone* equivale à luminância percebida e é o eixo usado para garantir contraste.

### 3.2 Color roles

**Accent (primary, secondary, tertiary):**

| Papel | Uso oficial |
|---|---|
| `primary` | Preenchimentos, textos e ícones de alta ênfase sobre surface (FAB, botões de alta ênfase, estados ativos) |
| `on-primary` | Texto e ícone sobre `primary` |
| `primary-container` | Preenchimento de destaque sobre surface para componentes-chave (ex.: FAB) |
| `on-primary-container` | Texto e ícone sobre `primary-container` |
| `secondary` / `on-secondary` | Elementos menos proeminentes (ex.: filter chips) |
| `secondary-container` / `on-secondary-container` | Componentes recessivos, como tonal buttons; também o estado "activated" (item selecionado de navegação) |
| `tertiary` / `on-tertiary` / `tertiary-container` / `on-tertiary-container` | Acentos contrastantes que equilibram primary e secondary ou chamam atenção para um elemento (badge, campo de entrada) |
| `inverse-primary` | Ações (ex.: text button) sobre `inverse-surface` |

**Error:** `error`, `on-error`, `error-container`, `on-error-container`. Não existe papel oficial de "warning" ou "success" no M3; ver 3.6.

**Surfaces:**

| Papel | Uso oficial |
|---|---|
| `surface` | Fundo padrão |
| `on-surface` | Texto e ícone sobre qualquer surface |
| `on-surface-variant` | Texto e ícone de menor ênfase sobre surface |
| `surface-container-lowest` | Container de menor ênfase |
| `surface-container-low` | Baixa ênfase (ex.: elevated button, elevated card) |
| `surface-container` | Container padrão (ex.: navigation bar, menu) |
| `surface-container-high` | Alta ênfase (ex.: basic dialog, search bar) |
| `surface-container-highest` | Maior ênfase (ex.: filled card, filled text field, switch desligado) |
| `surface-dim` / `surface-bright` | Variações de surface que permanecem mais escura ou mais clara nos dois temas |
| `surface-variant` | Papel legado; no Flutter `surfaceVariant` está deprecado em favor de `surfaceContainerHighest` |
| `background` / `on-background` | Legados; no Flutter estão deprecados em favor de `surface` / `onSurface` |

Os cinco `surface-container-*` servem para criar hierarquia e containers aninhados, especialmente em telas expandidas.

**Inverse:** `inverse-surface` (fundo que contrasta com surface), `inverse-on-surface` (texto sobre ele), `inverse-primary`. Uso canônico: **snackbar** (fundo `inverse-surface`, texto `inverse-on-surface`, ação em `inverse-primary`).

**Outline:**
- `outline`: limites importantes (borda de text field, limites de alvos interativos). Garante 3:1 com surface.
- `outline-variant`: elementos decorativos, como **divisores**, e bordas de cards. Pode ser usado em chips e botões **somente** se o conteúdo interno já tiver contraste 4.5:1.
- Não use `outline` para divisores nem para cards; não use `outline-variant` para definir hierarquia ou o limite de um alvo.

**Outros:** `scrim` (fundo atrás de modais), `shadow`.

**Add-on (opcionais):** `primary-fixed`, `primary-fixed-dim`, `on-primary-fixed`, `on-primary-fixed-variant` e equivalentes para secondary e tertiary. Mantêm a mesma cor nos dois temas. A documentação diz: "se você não tem certeza se precisa deles, provavelmente não precisa".

**Regra de pareamento:** sempre combine um container com seu "on" correspondente (`primary` + `on-primary`, `secondary-container` + `on-secondary-container`). Combinações cruzadas (ex.: `primary-container` + `on-surface`) quebram a legibilidade quando o nível de contraste muda.

### 3.3 Esquema baseline (estático) claro e escuro

Valores resolvidos a partir dos tokens oficiais (material-web `tokens/versions/latest`) e conferidos com `_colorSchemeLightM3` / `_colorSchemeDarkM3` do Flutter (`theme_data.dart`), que batem.

| Papel | Light: tom | Light: hex | Dark: tom | Dark: hex |
|---|---|---|---|---|
| primary | primary40 | `#6750A4` | primary80 | `#D0BCFF` |
| on-primary | primary100 | `#FFFFFF` | primary20 | `#381E72` |
| primary-container | primary90 | `#EADDFF` | primary30 | `#4F378B` |
| on-primary-container | primary30 | `#4F378B` | primary90 | `#EADDFF` |
| inverse-primary | primary80 | `#D0BCFF` | primary40 | `#6750A4` |
| secondary | secondary40 | `#625B71` | secondary80 | `#CCC2DC` |
| on-secondary | secondary100 | `#FFFFFF` | secondary20 | `#332D41` |
| secondary-container | secondary90 | `#E8DEF8` | secondary30 | `#4A4458` |
| on-secondary-container | secondary30 | `#4A4458` | secondary90 | `#E8DEF8` |
| tertiary | tertiary40 | `#7D5260` | tertiary80 | `#EFB8C8` |
| on-tertiary | tertiary100 | `#FFFFFF` | tertiary20 | `#492532` |
| tertiary-container | tertiary90 | `#FFD8E4` | tertiary30 | `#633B48` |
| on-tertiary-container | tertiary30 | `#633B48` | tertiary90 | `#FFD8E4` |
| error | error40 | `#B3261E` | error80 | `#F2B8B5` |
| on-error | error100 | `#FFFFFF` | error20 | `#601410` |
| error-container | error90 | `#F9DEDC` | error30 | `#8C1D18` |
| on-error-container | error30 | `#8C1D18` | error90 | `#F9DEDC` |
| surface | neutral98 | `#FEF7FF` | neutral6 | `#141218` |
| on-surface | neutral10 | `#1D1B20` | neutral90 | `#E6E0E9` |
| surface-variant | neutral-variant90 | `#E7E0EC` | neutral-variant30 | `#49454F` |
| on-surface-variant | neutral-variant30 | `#49454F` | neutral-variant80 | `#CAC4D0` |
| surface-dim | neutral87 | `#DED8E1` | neutral6 | `#141218` |
| surface-bright | neutral98 | `#FEF7FF` | neutral24 | `#3B383E` |
| surface-container-lowest | neutral100 | `#FFFFFF` | neutral4 | `#0F0D13` |
| surface-container-low | neutral96 | `#F7F2FA` | neutral10 | `#1D1B20` |
| surface-container | neutral94 | `#F3EDF7` | neutral12 | `#211F26` |
| surface-container-high | neutral92 | `#ECE6F0` | neutral17 | `#2B2930` |
| surface-container-highest | neutral90 | `#E6E0E9` | neutral22 | `#36343B` |
| inverse-surface | neutral20 | `#322F35` | neutral90 | `#E6E0E9` |
| inverse-on-surface | neutral95 | `#F5EFF7` | neutral20 | `#322F35` |
| outline | neutral-variant50 | `#79747E` | neutral-variant60 | `#938F99` |
| outline-variant | neutral-variant80 | `#CAC4D0` | neutral-variant30 | `#49454F` |
| scrim | neutral0 | `#000000` | neutral0 | `#000000` |
| shadow | neutral0 | `#000000` | neutral0 | `#000000` |
| primary-fixed | primary90 | `#EADDFF` | primary90 | `#EADDFF` |
| primary-fixed-dim | primary80 | `#D0BCFF` | primary80 | `#D0BCFF` |
| on-primary-fixed | primary10 | `#21005D` | primary10 | `#21005D` |
| on-primary-fixed-variant | primary30 | `#4F378B` | primary30 | `#4F378B` |

Observação: nos tokens atuais, `on-*-container` no tema claro usa o **tom 30** (versões antigas da especificação usavam tom 10, como `#21005D`). O Flutter atual também usa tom 30.

Mudanças técnicas registradas em fev/2023: surface padrão do light passou de tone 99 para tone 98, chroma da paleta neutral subiu de 4 para 6 e as surfaces do dark ficaram levemente mais escuras.

### 3.4 Tonal palettes do baseline (referência)

| Tom | primary | secondary | tertiary | error | neutral | neutral-variant |
|---|---|---|---|---|---|---|
| 0 | `#000000` | `#000000` | `#000000` | `#000000` | `#000000` | `#000000` |
| 10 | `#21005D` | `#1D192B` | `#31111D` | `#410E0B` | `#1D1B20` | `#1D1A22` |
| 20 | `#381E72` | `#332D41` | `#492532` | `#601410` | `#322F35` | `#322F37` |
| 30 | `#4F378B` | `#4A4458` | `#633B48` | `#8C1D18` | `#48464C` | `#49454F` |
| 40 | `#6750A4` | `#625B71` | `#7D5260` | `#B3261E` | `#605D64` | `#605D66` |
| 50 | `#7F67BE` | `#7A7289` | `#986977` | `#DC362E` | `#79767D` | `#79747E` |
| 60 | `#9A82DB` | `#958DA5` | `#B58392` | `#E46962` | `#938F96` | `#938F99` |
| 70 | `#B69DF8` | `#B0A7C0` | `#D29DAC` | `#EC928E` | `#AEA9B1` | `#AEA9B4` |
| 80 | `#D0BCFF` | `#CCC2DC` | `#EFB8C8` | `#F2B8B5` | `#CAC5CD` | `#CAC4D0` |
| 90 | `#EADDFF` | `#E8DEF8` | `#FFD8E4` | `#F9DEDC` | `#E6E0E9` | `#E7E0EC` |
| 95 | `#F6EDFF` | `#F6EDFF` | `#FFECF1` | `#FCEEEE` | `#F5EFF7` | `#F5EEFA` |
| 98 | `#FEF7FF` | `#FEF7FF` | `#FFF8F8` | `#FFF8F7` | `#FEF7FF` | `#FDF7FF` |
| 99 | `#FFFBFE` | `#FFFBFE` | `#FFFBFA` | `#FFFBF9` | `#FFFBFF` | `#FFFBFE` |
| 100 | `#FFFFFF` | `#FFFFFF` | `#FFFFFF` | `#FFFFFF` | `#FFFFFF` | `#FFFFFF` |

Tons extras da neutral: 4 `#0F0D13`, 6 `#141218`, 12 `#211F26`, 17 `#2B2930`, 22 `#36343B`, 24 `#3B383E`, 87 `#DED8E1`, 92 `#ECE6F0`, 94 `#F3EDF7`, 96 `#F7F2FA`.

### 3.5 Esquema estático x dinâmico; gerar a partir de uma source color

**Estático (baseline):** cores nunca mudam. Recomendado pela documentação quando o produto é para uso corporativo, quando não se quer personalização ou quando ainda não se está pronto para cor dinâmica. Não oferece contraste controlado pelo usuário.

**Dinâmico:**
- *User-generated:* source color extraída do papel de parede (fluxo do Android).
- *Content-based:* source color extraída de conteúdo do app (capa de álbum, imagem) via quantização.
- Mesmo usando cor dinâmica, a recomendação é desenhar primeiro com o baseline e validar com o **Material Theme Builder** em várias source colors.

**Para o disk-cleanup:** o Linux desktop não fornece cor de papel de parede no fluxo do Android. A abordagem indicada é **esquema gerado a partir de uma source color fixa da marca** (cor da marca como seed), com light e dark. Opcionalmente, um seletor de cor de destaque nas configurações, regenerando o esquema.

**Variantes de esquema** (`DynamicSchemeVariant` do Flutter, espelhando `Variant` do material-color-utilities):

| Variante | Descrição oficial (api.flutter.dev) |
|---|---|
| `tonalSpot` | **Padrão.** Paletas pastel com chroma baixo |
| `fidelity` | Paletas fiéis à seed, mesmo com seed muito saturada |
| `content` | Quase igual a `fidelity`; `primaryContainer` é a seed ajustada para contraste; tertiary é análoga da seed |
| `vibrant` | Chroma da paleta primary no máximo |
| `expressive` | Chroma médio; hue da primary diferente da seed |
| `neutral` | Quase cinza, com leve chroma |
| `monochrome` | Totalmente cinza |
| `rainbow`, `fruitSalad` | Temas lúdicos; o hue da seed não aparece |

**Contraste:** o esquema aceita `contrastLevel` (0.0 padrão; o material-web publica conjuntos de tokens "medium-contrast" e "high-contrast"). Em Flutter, `ColorScheme.fromSeed(contrastLevel: ...)`. Os valores exatos de cada nível no Flutter (por exemplo 0.5 e 1.0) são **(não confirmado)**.

**Flutter:**

```dart
final light = ColorScheme.fromSeed(
  seedColor: const Color(0xFF6750A4),
  brightness: Brightness.light,
  dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
  contrastLevel: 0.0,
);
final dark = ColorScheme.fromSeed(
  seedColor: const Color(0xFF6750A4),
  brightness: Brightness.dark,
);

MaterialApp(
  theme: ThemeData(colorScheme: light),
  darkTheme: ThemeData(colorScheme: dark),
  themeMode: ThemeMode.system,
);
```

Assinatura confirmada: `ColorScheme.fromSeed({required Color seedColor, Brightness brightness = Brightness.light, DynamicSchemeVariant dynamicSchemeVariant = DynamicSchemeVariant.tonalSpot, double contrastLevel = 0.0, ...overrides de cada papel})`. Atalho: `ThemeData(colorSchemeSeed: ...)`. Também existe `ColorScheme.fromImageProvider` para cor baseada em conteúdo.

**Web (protótipo):** gerar os hex com o Material Theme Builder ou com `material-color-utilities` (TypeScript) e colar como `--md-sys-color-*` em `:root`, como recomenda a documentação do material-web.

### 3.6 Cores semânticas extras (aviso, sucesso)

O M3 não define papéis `warning` ou `success`. Para o disk-cleanup (alertas de disco quase cheio), o caminho coerente com o sistema é:

- **Crítico** (disco acima do limite configurado, falha): papéis `error` / `error-container`.
- **Aviso** e **sucesso:** cores customizadas **harmonizadas** com a source color (o material-color-utilities oferece `blend` para harmonizar em HCT; o Material Theme Builder tem "custom colors" com harmonização). Cada cor customizada deve ganhar o mesmo quarteto de papéis (`x`, `on-x`, `x-container`, `on-x-container`) em light e dark.
- Em Flutter, essas cores vão numa `ThemeExtension` (ver seção 14).
- Nunca comunique estado só por cor: acompanhe com ícone (`warning`, `error`, `check_circle`) e texto.

---

## 4. Tipografia

### 4.1 Estrutura

- 5 papéis: **display, headline, title, body, label**; cada um em **large, medium, small** = 15 estilos baseline.
- M3 Expressive acrescentou 15 estilos **emphasized** (peso maior). Não disponíveis no Flutter (os tokens existem no material-web; valores não detalhados aqui).
- Dois "typefaces" de referência: **brand** (display, headline, title-large) e **plain** (title-medium/small, body, label). Ambos são **Roboto** por padrão. Pesos de referência: regular 400, medium 500, bold 700.
- A escala é baseada na Major Second, com 14 como tamanho-base.
- Fallback recomendado quando se usa Roboto Flex: Roboto Flex → Roboto → Noto Sans. Para números alinhados (tabelas de tamanhos de arquivo), a documentação aponta **Roboto Mono** como opção monoespaçada.

Uso de cada papel (resumo oficial):
- **Display:** textos curtos e importantes ou numerais; funciona melhor em telas grandes. Bom para o número grande de "espaço livre" no dashboard.
- **Headline:** textos curtos de alta ênfase; marcar regiões principais.
- **Title:** ênfase média, textos curtos; dividir regiões secundárias, títulos de cards e da top app bar.
- **Body:** texto corrido.
- **Label:** textos de componentes (botões, chips, abas, rótulos de navegação).
- Em qualquer breakpoint, ajuste margens e estilos para manter 40 a 60 caracteres por linha.

### 4.2 Type scale completa (baseline)

Valores dos tokens `md.sys.typescale.*` (material-web latest), conferidos com `_M3Typography.englishLike` do Flutter. 1rem = 16px.

| Estilo | Tamanho | Line-height | Peso | Tracking | Typeface | Flutter `height` |
|---|---|---|---|---|---|---|
| display-large | 57px (3.5625rem) | 64px (4rem) | 400 | -0.25px (-0.015625rem) | brand | 1.12 |
| display-medium | 45px (2.8125rem) | 52px (3.25rem) | 400 | 0 | brand | 1.16 |
| display-small | 36px (2.25rem) | 44px (2.75rem) | 400 | 0 | brand | 1.22 |
| headline-large | 32px (2rem) | 40px (2.5rem) | 400 | 0 | brand | 1.25 |
| headline-medium | 28px (1.75rem) | 36px (2.25rem) | 400 | 0 | brand | 1.29 |
| headline-small | 24px (1.5rem) | 32px (2rem) | 400 | 0 | brand | 1.33 |
| title-large | 22px (1.375rem) | 28px (1.75rem) | 400 | 0 | brand | 1.27 |
| title-medium | 16px (1rem) | 24px (1.5rem) | 500 | 0.15px (0.009375rem) | plain | 1.50 |
| title-small | 14px (0.875rem) | 20px (1.25rem) | 500 | 0.1px (0.00625rem) | plain | 1.43 |
| body-large | 16px (1rem) | 24px (1.5rem) | 400 | 0.5px (0.03125rem) | plain | 1.50 |
| body-medium | 14px (0.875rem) | 20px (1.25rem) | 400 | 0.25px (0.015625rem) | plain | 1.43 |
| body-small | 12px (0.75rem) | 16px (1rem) | 400 | 0.4px (0.025rem) | plain | 1.33 |
| label-large | 14px (0.875rem) | 20px (1.25rem) | 500 | 0.1px (0.00625rem) | plain | 1.43 |
| label-medium | 12px (0.75rem) | 16px (1rem) | 500 | 0.5px (0.03125rem) | plain | 1.33 |
| label-small | 11px (0.6875rem) | 16px (1rem) | 500 | 0.5px (0.03125rem) | plain | 1.45 |

Os tokens também declaram `label-*-weight-prominent` = 700 (bold).

**Flutter:** `ThemeData.textTheme` com os campos `displayLarge` … `labelSmall` (mesmos nomes em camelCase). Leitura: `Theme.of(context).textTheme.titleMedium` ou `TextTheme.of(context)`. Para trocar a fonte inteira: `ThemeData(fontFamily: 'Roboto')` ou `textTheme.apply(fontFamily: ...)`. No Linux, empacote a fonte no app (assets) para não depender da fonte do sistema. Para colunas numéricas, `FontFeature.tabularFigures()` no `TextStyle`.

---

## 5. Shape (forma)

### 5.1 Escala de corner radius

| Token | Valor | Status |
|---|---|---|
| `corner-none` | 0dp | baseline |
| `corner-extra-small` | 4dp | baseline |
| `corner-small` | 8dp | baseline |
| `corner-medium` | 12dp | baseline |
| `corner-large` | 16dp | baseline |
| `corner-large-increased` | 20dp | M3 Expressive (maio/2025) |
| `corner-extra-large` | 28dp | baseline |
| `corner-extra-large-increased` | 32dp | M3 Expressive |
| `corner-extra-extra-large` | 48dp | M3 Expressive |
| `corner-full` | totalmente arredondado (token CSS: 9999px; antes definido como 50% do tamanho) | baseline |

Variantes assimétricas: `extra-small-top` (4 4 0 0), `large-top` (16 16 0 0), `large-start` (16 0 0 16), `large-end` (0 16 16 0), `extra-large-top` (28 28 0 0).

### 5.2 Onde cada nível se aplica (tokens de componente do material-web)

| Nível | Componentes |
|---|---|
| none | full-screen dialog, navigation rail (container), navigation bar, tabs, progress indicators |
| extra-small | menu, snackbar, plain tooltip, outlined text field |
| extra-small-top | filled text field |
| small | chips (assist, filter, input) |
| medium | cards (elevated, filled, outlined), rich tooltip, icon button "square" |
| large | FAB, extended FAB, lista (container) |
| large-end | navigation drawer |
| extra-large | basic dialog |
| extra-large-top | bottom sheet **(não confirmado; o arquivo de token consultado não declara o valor)** |
| full | botões, icon buttons (round), badge, slider, switch, search bar, indicadores ativos de navigation rail, bar e drawer |

Regras oficiais:
- Ajustar um nível (ex.: `medium`) muda todos os componentes mapeados a ele. Para mudar um componente só, remapeie o componente para outro nível.
- **Não aplique `large` ou `full` em componentes densos em informação, como cards.** Relevante para os cards de diretórios e de consumidores.
- Existe a família "cut" (cantos chanfrados), que exige padding extra.

**Flutter:** não há tokens de sistema de shape no `ThemeData`. Os componentes já usam os raios M3 por padrão. Para reutilizar a escala em widgets próprios, crie uma `ThemeExtension` (seção 14) ou constantes (`BorderRadius.circular(12)` para medium). Para sobrescrever um componente: `cardTheme: CardThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))`, `filledButtonTheme`, `dialogTheme` etc.

---

## 6. Elevation

### 6.1 Níveis

| Nível | dp | Uso típico (tokens de componente) |
|---|---|---|
| level0 | 0 | filled/outlined card, filled/tonal/outlined/text button, navigation rail, full-screen dialog |
| level1 | 1 | elevated card, elevated button |
| level2 | 3 | menu, navigation bar, rich tooltip |
| level3 | 6 | basic dialog, FAB, snackbar, search bar, search view |
| level4 | 8 | reservado para estados de interação (hover) |
| level5 | 12 | reservado para estados de interação (dragged) |

Regras oficiais:
- Estado de repouso fica entre 0 e +3; +4 e +5 são para estados interativos (hover, dragged).
- Todos os botões Material sobem 1 nível no hover (ex.: FAB de 3 para 4).
- Elevação pode ser expressa por **cor tonal** (surface containers diferentes), **sombra** ou **scrim**. No M3 a sombra é usada só quando é preciso proteção extra contra o fundo ou para incentivar interação.
- Use poucos níveis: quanto menos níveis, mais força cada um tem.
- `surface-tint` foi descontinuado; use os níveis e os papéis `surface-container-*`.
- Evite mudar a elevação padrão dos componentes M3.

**Flutter:** `elevation` em dp (`double`) nos componentes e temas. No M3 do Flutter, a diferenciação tonal vem de `surfaceContainer*`; `surfaceTintColor` ainda existe na API mas o conceito foi descontinuado na especificação. Para desligar tint residual em algum componente: `surfaceTintColor: Colors.transparent` **(não confirmado se ainda é necessário em 3.47)**.

---

## 7. Motion

### 7.1 Situação atual

No M3 Expressive, os componentes passaram a usar **springs** (física). O sistema de easing e duração "ainda é usado para transições", mas "não é mais mantido". Como o Flutter não implementa o Expressive, **o disk-cleanup usa easing e duração**.

Tokens de spring (somente referência; não existem no Flutter): `spring-default-spatial` (damping 0.9, stiffness 700), `spring-default-effects` (1, 1600), `spring-fast-spatial` (0.9, 1400), `spring-fast-effects` (1, 3800), `spring-slow-spatial` (0.9, 300), `spring-slow-effects` (1, 800).

### 7.2 Durações

| Token | Valor | Flutter |
|---|---|---|
| short1 / short2 / short3 / short4 | 50 / 100 / 150 / 200ms | `Durations.short1` … `short4` |
| medium1 / medium2 / medium3 / medium4 | 250 / 300 / 350 / 400ms | `Durations.medium1` … `medium4` |
| long1 / long2 / long3 / long4 | 450 / 500 / 550 / 600ms | `Durations.long1` … `long4` |
| extra-long1 / 2 / 3 / 4 | 700 / 800 / 900 / 1000ms | `Durations.extralong1` … `extralong4` |

### 7.3 Easings

| Token | Curva | Flutter |
|---|---|---|
| emphasized | Path de duas cúbicas: `M 0,0 C 0.05,0 0.133333,0.06 0.166666,0.4 C 0.208333,0.82 0.25,1 1,1`. Na web não há equivalente exato; o material-web usa `cubic-bezier(0.2, 0, 0, 1)` como aproximação | `Curves.easeInOutCubicEmphasized` (ThreePointCubic com os mesmos pontos) |
| emphasized-decelerate | `cubic-bezier(0.05, 0.7, 0.1, 1)` | `Easing.emphasizedDecelerate` |
| emphasized-accelerate | `cubic-bezier(0.3, 0, 0.8, 0.15)` | `Easing.emphasizedAccelerate` |
| standard | `cubic-bezier(0.2, 0, 0, 1)` | `Easing.standard` |
| standard-decelerate | `cubic-bezier(0, 0, 0, 1)` | `Easing.standardDecelerate` |
| standard-accelerate | `cubic-bezier(0.3, 0, 1, 1)` | `Easing.standardAccelerate` |
| linear | `cubic-bezier(0, 0, 1, 1)` | `Easing.linear` |
| legacy / legacy-decelerate / legacy-accelerate | `(0.4,0,0.2,1)` / `(0,0,0.2,1)` / `(0.4,0,1,1)` | `Easing.legacy*` |

O path do emphasized foi extraído da `ThreePointCubic` do Flutter (pontos (0.05,0), (0.133333,0.06), (0.166666,0.4), (0.208333,0.82), (0.25,1)).

### 7.4 Combinações recomendadas (padrões oficiais)

| Easing | Duração | Tipo de transição |
|---|---|---|
| Emphasized | 500ms | Começa e termina na tela |
| Emphasized decelerate | 400ms | Entra na tela |
| Emphasized accelerate | 200ms | Sai da tela |
| Standard | 300ms | Começa e termina na tela |
| Standard decelerate | 250ms | Entra na tela |
| Standard accelerate | 200ms | Sai da tela |

- Emphasized é o conjunto recomendado para a maioria das transições. Standard é para transições pequenas e utilitárias, e é o fallback para plataformas sem Emphasized (iOS e Web).
- Controles de seleção (checkbox, switch) usam 200ms com Standard.
- Saída com accelerate passa a ideia de que o elemento não volta (bom para item removido após limpeza).

---

## 8. Layout

### 8.1 Breakpoints (window size classes)

O M3 renomeou "window size classes" para **breakpoints**. São definidos pelo espaço disponível na janela, não pelo dispositivo.

| Breakpoint | Largura | Panes recomendados | Navegação | Margens | Spacer entre panes |
|---|---|---|---|---|---|
| Compact | < 600dp | 1 | Navigation bar ou modal expanded navigation rail | 16dp | n/a |
| Medium | 600 a 839dp | 1 (recomendado) ou 2 | Rail com 1 pane; navigation bar com 2 panes | 24dp | 24dp |
| Expanded | 840 a 1199dp | 2 (recomendado) ou 1 | Navigation rail (recolhido ou expandido) | 24dp | 24dp |
| Large | 1200 a 1599dp | 2 (recomendado) ou 1 | Navigation rail (recolhido ou expandido) | 24dp | 24dp |
| Extra-large | ≥ 1600dp | 2 (recomendado), 1 ou 3 | Rail expandido é o mais indicado | 24dp | 24dp |

Height breakpoints (Android): compact < 480dp, medium 480 a 899dp, expanded ≥ 900dp. Raramente necessários, porque o conteúdo costuma rolar verticalmente.

Componentes de comunicação e ação por breakpoint: compact usa simple dialog, full-screen dialog e bottom sheet; medium em diante usa simple dialog e menu.

**Para o disk-cleanup (desktop):** a janela típica fica em expanded ou large. Porém a janela é redimensionável e pode ficar estreita (tiling, meia tela), então o layout deve responder a todos os breakpoints.

### 8.2 Panes

- Todo layout tem de 1 a 3 panes visíveis e pelo menos um pane flexível.
- **Fixed-and-flexible:** pane fixo com **360dp** em expanded e **412dp** em large e extra-large. O pane fixo costuma ser temporário (side sheet, lista de baixa densidade).
- **Split-pane:** dois panes flexíveis com o spacer visualmente centralizado; quando há navigation rail, ela reduz só o primeiro pane, e "rail + primeiro pane" ocupam 50% da janela.
- **Três panes:** só em extra-large, com um standard side sheet como terceiro pane (largura máxima padrão de side sheet: 400dp). Nunca mais de três.
- Panes podem ser redimensionados por drag handle, com snap em 360dp, 412dp ou split centralizado. A largura escolhida pelo usuário deve persistir, inclusive após troca de breakpoint e reabertura do app.
- Layouts canônicos: list-detail, supporting pane, feed.

Aplicação sugerida no disk-cleanup:
- **Explorador de arquivos grandes / diretórios mapeados:** list-detail (lista no pane fixo de 360 ou 412dp, detalhes e ações no pane flexível). Em compact, vira navegação lista → detalhe.
- **Dashboard:** pane único flexível com grid de cards; em extra-large, um side sheet com alertas recentes.

### 8.3 Grid e espaçamento

- Escala de espaçamento em **8dp** (`space100` = 8dp), com unidades aninhadas de 2, 4, 6 e 10dp. Os tokens `md.sys.measurement.space*` existem só no Jetpack Compose.
- Categorias: **padding** (dentro do elemento), **gap** (entre elementos), **margin** (fora do elemento); posições leading/trailing invertem em RTL.
- O número de colunas do grid muda com o breakpoint (ex.: 4 colunas em compact; exemplos com 8 colunas em tablet). Os números exatos de colunas por breakpoint são **(não confirmado)**.
- Ao escalar texto para 200%, o espaçamento padrão deve ser preservado.

**Densidade:**
- Escala numérica a partir de 0 (padrão) para -1, -2, -3; cada passo reduz tipicamente 4dp de padding vertical ou altura.
- O usuário deve **optar** por densidade alta; alvos interativos continuam com mínimo de 48x48dp.

**Flutter:** não há classe de breakpoint no pacote `material`. Use `MediaQuery.sizeOf(context).width` com os limiares acima (Flutter usa pixels lógicos, equivalentes a dp). Densidade: `ThemeData.visualDensity` (`VisualDensity.compact`, `standard`, `comfortable`). Para desktop, o Flutter aplica `VisualDensity.adaptivePlatformDensity` por padrão **(não confirmado em 3.47)**.

```dart
enum Breakpoint { compact, medium, expanded, large, extraLarge }

Breakpoint breakpointOf(double width) => switch (width) {
      < 600 => Breakpoint.compact,
      < 840 => Breakpoint.medium,
      < 1200 => Breakpoint.expanded,
      < 1600 => Breakpoint.large,
      _ => Breakpoint.extraLarge,
    };
```

---

## 9. State layers e estados

### 9.1 State layers

- Camada semitransparente entre o container e o conteúdo. Cor = cor do conteúdo (normalmente o papel "on-*" correspondente).
- Uma única state layer por vez.
- Tamanho da state layer: **40dp**; alvo interativo: **48dp**.

| Estado | Opacidade (spec atual) | Token |
|---|---|---|
| Hover | 8% | `md.sys.state.hover.state-layer-opacity` = 0.08 |
| Focus | 10% | `md.sys.state.focus.state-layer-opacity` = 0.10 |
| Pressed | 10% | `md.sys.state.pressed.state-layer-opacity` = 0.10 |
| Dragged | 16% | `md.sys.state.dragged.state-layer-opacity` = 0.16 |
| Disabled | conteúdo a 38%; container `on-surface` a 12% | `md.sys.state.disabled.state-layer-opacity` = 0.38 |

Versões antigas dos tokens (v0_192) usavam 12% para focus e pressed. O Flutter atual usa 0.08 (hover), 0.10 (focus) e 0.10 (pressed) nos botões, e `onSurface` a 0.12 / 0.38 para fundo e rótulo desabilitados (fonte: `filled_button.dart`).

**Activated:** componentes ativados (item selecionado de navegação) não usam state layer; trocam o container para `secondary-container` e o conteúdo para `on-secondary-container`.

### 9.2 Indicador de foco (tokens atuais)

`md.sys.state.focus-indicator.thickness` = 3dp, `outer-offset` = 2dp, `inner-offset` = -3dp.

### 9.3 Herança de estados

- Disabled e hover são herdados por componentes de ação, seleção e entrada (botões, cards, checkbox, chips, itens de lista, radio, switch, text fields, slider).
- Não são herdados por componentes de comunicação, contenção e navegação (app bars, badges, dialogs, menus, navigation bar/drawer/rail, sheets, tabs, tooltips). Exemplo: numa app bar, apenas as ações internas recebem hover, não a barra inteira.
- Componentes desabilitados não recebem foco, não são arrastados nem pressionados. Estados desabilitados não precisam cumprir os requisitos de contraste.

**Flutter:** `WidgetStateProperty` (antes `MaterialStateProperty`) em `ButtonStyle.overlayColor`, `backgroundColor` etc. Exemplo para widgets próprios:

```dart
overlayColor: WidgetStateProperty.resolveWith((states) {
  final c = Theme.of(context).colorScheme.onSurface;
  if (states.contains(WidgetState.pressed)) return c.withValues(alpha: 0.10);
  if (states.contains(WidgetState.focused)) return c.withValues(alpha: 0.10);
  if (states.contains(WidgetState.hovered)) return c.withValues(alpha: 0.08);
  return null;
}),
```

---

## 10. Componentes

Formato: quando usar (diretriz oficial), equivalente Flutter e aplicação no disk-cleanup.

### 10.1 Navegação

**Navigation rail**
- Para breakpoints medium, expanded, large e extra-large; 3 a 7 destinos mais um FAB opcional; sempre no mesmo lugar em todas as telas; não usar na horizontal; não colocar o FAB abaixo dos itens; indicador ativo só na página atual. Dimensões (tokens): largura 80dp, indicador ativo 32dp de altura, shape `full`.
- Pode alternar entre recolhido e expandido pelo ícone de menu.
- **Flutter:** `NavigationRail(destinations: [NavigationRailDestination(...)], selectedIndex:, onDestinationSelected:, extended: bool, labelType:, leading:, trailing:)`. `extended: true` equivale ao rail expandido.
- **disk-cleanup:** navegação principal (Dashboard, Maiores consumidores, Diretórios, Explorador, Limpeza, Docker, Configurações = 7 destinos, no limite). `extended: true` em large e extra-large; recolhido em medium e expanded.

**Navigation drawer**
- Para 5 ou mais destinos primários ou mais de um nível de hierarquia. Standard em expanded e acima; modal em compact e medium. Não usar dois componentes de navegação na mesma tela. Divisores de largura total só entre grupos. Container: largura 360dp, shape `large-end`, indicador ativo com 56dp de altura.
- No M3 Expressive ele "não é mais recomendado" (substituído pelo expanded navigation rail). No Flutter continua sendo o componente M3 disponível.
- **Flutter:** `NavigationDrawer(children: [NavigationDrawerDestination(...)], selectedIndex:, onDestinationSelected:)` para modal (`Scaffold.drawer`) ou standard (dentro de um `Row`).
- **disk-cleanup:** usar apenas como modal em compact, ou preferir rail sempre.

**Navigation bar** (para referência em janelas compact): 3 a 5 destinos em compact e medium. Flutter: `NavigationBar` + `NavigationDestination`.

### 10.2 Top app bar

- Descreve a página atual e oferece 1 a 2 ações essenciais (para mais ações de página, use toolbar). Variantes atuais: search app bar, small, medium flexible, large flexible (medium e large baseline foram substituídos no Expressive). Ao rolar, recebe fill para se separar do conteúdo. Use filled ou tonal button para ações importantes, mas nunca vários filled/tonal na mesma barra.
- **Flutter:** `AppBar` (small), `SliverAppBar.medium`, `SliverAppBar.large`. `scrolledUnderElevation` controla o fill ao rolar.
- **disk-cleanup:** título da seção + ação "Escanear novamente" (`refresh`) + menu overflow (`more_vert`).

### 10.3 Cards

- Contêm elementos relacionados a um único assunto; devem ser fáceis de escanear. Não force conteúdo em cards quando espaçamento, headlines ou divisores bastam; não role dentro de um card.
- Variantes e tokens:
  - **Elevated:** `surface-container-low`, level1, `corner-medium`.
  - **Filled:** `surface-container-highest`, level0, `corner-medium`.
  - **Outlined:** `surface`, level0, borda 1dp `outline-variant`, `corner-medium`.
- **Flutter:** `Card()` (elevated), `Card.filled()`, `Card.outlined()`.
- **disk-cleanup:** dashboard com cards filled (uso do disco, espaço recuperável, último scan); cards outlined para itens da tela de limpeza (Caches, Lixeira, Builds, Docker), cada um com tamanho e ação.

### 10.4 Lists

- Para encontrar um item e agir sobre ele; ordem lógica (alfabética, numérica, por tamanho); itens curtos; formato consistente de ícone, texto e ação. Use texto trailing para detalhes suplementares (preço, contagem, data, ou tamanho). Evite visuais no centro da linha. Estilos standard e segmented. Container: `corner-large` (tokens).
- **Flutter:** `ListView` + `ListTile(leading:, title:, subtitle:, trailing:)`; `CheckboxListTile`, `SwitchListTile`.
- **disk-cleanup:** "Maiores consumidores": `ListTile` com ícone de pasta, caminho no title, tipo/data no subtitle e tamanho no trailing (fonte tabular).

### 10.5 Data tables

- **O M3 não tem componente de data table** (não há página de data tables no sitemap do m3.material.io).
- **Flutter:** `DataTable` e `PaginatedDataTable` existem, mas a própria documentação diz que `DataTable` "follows the Material 2 design specification" e é caro para muitas linhas (mede duas vezes).
- **disk-cleanup:** para o explorador com muitas linhas e ordenação por coluna, preferir uma tabela própria baseada em `ListView.builder` com cabeçalho fixo e tokens M3 (`title-small` no cabeçalho, `body-medium` nas células, divisores `outline-variant`). `DataTable` só para tabelas pequenas.

### 10.6 Buttons

O M3 tem 10 tipos de botão (button, toggle button, icon button, toggle icon button, split button, button groups, FAB, extended FAB, FAB menu); no Flutter estão disponíveis os do M3 original.

**Regra central:** cada tela deve ter **um único botão de alta ênfase** para a ação principal; os demais usam estilos de menor ênfase para criar hierarquia. Rótulos em sentence case, numa linha só; não fixe largura menor que o rótulo.

| Estilo | Quando usar | Tokens (container / rótulo / elevação) | Flutter |
|---|---|---|---|
| Filled | Ação mais importante, final de fluxo ("Salvar", "Confirmar") | `primary` / `on-primary` / level0 | `FilledButton`, `FilledButton.icon` |
| Filled tonal | Meio-termo entre filled e outlined; ação importante mas secundária | `secondary-container` / `on-secondary-container` / level0 | `FilledButton.tonal`, `FilledButton.tonalIcon` |
| Outlined | Ênfase média; ação importante mas não principal; pareia com filled como alternativa | sem fill, borda 1dp `outline` / `primary` | `OutlinedButton` |
| Text | Menor prioridade; dentro de cards, dialogs e snackbars; fundos simples | sem container / `primary` | `TextButton` |
| Elevated | Separação de fundo visualmente carregado; usar com parcimônia | `surface-container-low` / `primary` / level1 | `ElevatedButton` |

Altura padrão: 40dp (alvo de 48dp). Shape: `full`. Ícones: 20dp.

**FAB**
- Para a ação mais comum ou importante da tela, construtiva (criar, favoritar, compartilhar, iniciar processo). Nunca mais de um por tela; nem toda tela precisa. Extended FAB quando o rótulo é necessário. Small FAB não é mais recomendado (Expressive). Tokens: 56x56dp, `primary-container`/`on-primary-container` no FAB padrão do M3 original (os tokens atuais mostram `fab-primary` com `primary`), level3, `corner-large`.
- **Flutter:** `FloatingActionButton`, `FloatingActionButton.extended`, `.small`, `.large`.
- **disk-cleanup:** um extended FAB "Escanear" no dashboard é aceitável. **Não** use FAB para "Limpar" ou "Excluir": o FAB é para ações construtivas.

### 10.7 Icon buttons

- Devem usar um ícone de sistema com significado claro. Na web e no desktop, mostre tooltip descrevendo a ação no hover. Em toggle, ícone outlined para não selecionado e filled para selecionado.
- Estilos: standard (baixa ênfase), outlined (média), filled tonal, filled (alta ênfase; a documentação cita "baixar ou excluir" como exemplo de filled).
- Tokens: container 40dp, ícone 24dp, state layer 40dp.
- **Flutter:** `IconButton`, `IconButton.filled`, `IconButton.filledTonal`, `IconButton.outlined`; parâmetros `tooltip`, `isSelected`, `selectedIcon`.

### 10.8 Chips

- Mostram opções contextuais e suplementares; sempre em conjunto (nunca um chip sozinho); não substituem ações principais nem avançam fluxos (isso é papel de botões). Altura 32dp, `corner-small`.

| Tipo | Uso oficial | Flutter |
|---|---|---|
| Assist | Ações inteligentes ou automatizadas | `ActionChip` (e `ActionChip.elevated`) |
| Filter | Tags ou palavras para filtrar conteúdo; alternativa a segmented buttons ou checkboxes; ao ativar, ganha checkmark | `FilterChip` |
| Input | Informação discreta digitada pelo usuário; pode ser removível | `InputChip` (`onDeleted`) |
| Suggestion | Sugestões geradas dinamicamente | `ActionChip` **(mapeamento não confirmado)** |

Também existe `ChoiceChip` no Flutter (seleção única).

**disk-cleanup:** filter chips para o explorador (tipo: vídeo, imagem, arquivo compactado, ISO; idade: > 30 dias, > 1 ano); input chips para padrões de exclusão nas configurações (`node_modules`, `*.iso`).

### 10.9 Progress indicators (e loading indicator)

- Mostram o status de processos em andamento (carregar, enviar, salvar). Com vários itens carregando, use **um único** indicador para o grupo; não coloque indicador em cada item da lista.
- **Determinado:** preenche de 0% a 100%. **Indeterminado:** move-se ao longo de uma trilha fixa.
- Circular para atividades curtas e indeterminadas (< 5 s). Use stop indicator quando o indicador está dentro de um container de baixo contraste.
- Tokens linear: trilha e indicador com 4dp de altura.
- **Loading indicator** (Expressive) substitui o circular indeterminado no Android; não há widget equivalente confirmado no Flutter **(não confirmado)**.
- **Flutter:** `LinearProgressIndicator(value: 0.0..1.0 | null)`, `CircularProgressIndicator`. O parâmetro `year2023` está deprecado: defina `year2023: false` (ou configure `ProgressIndicatorThemeData`) para a aparência de 2024 (gap na trilha e stop indicator).
- **disk-cleanup:** scan de disco = `LinearProgressIndicator` determinado quando houver total conhecido, indeterminado na fase de contagem; limpeza = determinado com bytes liberados. Para a **barra de uso do disco** (que não é um processo), prefira um medidor próprio com os papéis de cor (`primary` para usado, `surface-container-highest` para livre, `error` acima do limite) em vez de reaproveitar o progress indicator, que tem semântica de processo **(recomendação deste documento)**.

### 10.10 Dialogs (basic e full-screen)

- Para prompts que bloqueiam a operação normal e para informação crítica que exige tarefa, decisão ou reconhecimento. Comumente usados para **confirmar ações de alto risco, como excluir**. Não use para informação de prioridade baixa ou média (use snackbar).
- Basic: `surface-container-high`, level3, `corner-extra-large`, sobre `scrim`. Full-screen: `surface`, `corner-none`.
- Full-screen só em breakpoints compact; em medium e acima, use basic.
- **Flutter:** `showDialog` + `AlertDialog(icon:, title:, content:, actions:)`; `AlertDialog.adaptive`; `Dialog.fullscreen` para full-screen; `SimpleDialog` para lista de opções.
- Regras de conteúdo e ações na seção 11.

### 10.11 Snackbars

- Mensagens minimamente interruptivas sobre um processo que o app fez ou fará; aparecem na parte inferior; uma por vez; no máximo **uma ação**; sem ícones; sem links ou texto estilizado; não use filled ou elevated button dentro dela. "Dismiss" é desnecessário se ela some sozinha.
- Para permitir que o usuário volte atrás, exiba a ação **"Desfazer" (Undo)**.
- Tokens: `inverse-surface`, level3, `corner-extra-small`; ação em `inverse-primary`.
- Acessibilidade: snackbar **com ação não deve sumir sozinha**; sem ação, pode sumir após tempo suficiente (duração comum aceitável: 4 a 10 s). Anunciar a mensagem (live region polite) sem mover o foco; Esc dispensa quando focada.
- **Flutter:** `ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:, action: SnackBarAction(label: 'Desfazer', onPressed: ...)))`. Padrões confirmados no código: duração de 4000ms; `persist` passa a ser `true` automaticamente quando há `action`, o que já segue a diretriz de acessibilidade. `behavior: SnackBarBehavior.floating` e `width` para desktop.

### 10.12 Banners

- **Não há página de banners no M3** (o sitemap do m3.material.io não lista o componente). O Flutter mantém `MaterialBanner`: mensagem importante e sucinta, com ações; só some por ação do usuário; persistente e não modal; posicionado no topo, abaixo da top app bar.
- **disk-cleanup:** útil para o **alerta persistente de disco quase cheio** no dashboard ("O disco / está com 94% de uso. Libere espaço para evitar falhas.", ações "Ver maiores consumidores" e "Ignorar"). Usar `ScaffoldMessenger.showMaterialBanner` ou `MaterialBanner` inline com cores `error-container`/`on-error-container` para o nível crítico.

### 10.13 Badges

- Labels ou números; small (ponto) e large (com texto); ancorados no canto superior trailing do ícone; máximo de 4 caracteres incluindo "+"; mantenha as cores padrão (se customizar, contraste mínimo 3:1). Large em espaços folgados (rail); small em espaços apertados (app bar).
- **Flutter:** `Badge(label:, child:)`, `Badge.count(count:, maxCount: 999)`; tamanhos padrão `smallSize` 6dp e `largeSize` 16dp.
- **disk-cleanup:** badge no destino "Limpeza" da rail indicando categorias com espaço recuperável; badge small em "Configurações" quando um alerta estiver desativado.

### 10.14 Menus

- Conjunto temporário de ações (para ações sempre visíveis, use toolbar). Abrem a partir de icon buttons, split buttons, text fields; menus de contexto abrem com clique secundário. Tokens: `surface-container`, level2, `corner-extra-small`.
- **Flutter:** `MenuAnchor` + `MenuItemButton` / `SubmenuButton`; `MenuBar`; `DropdownMenu` para seleção; `PopupMenuButton` (API mais antiga).
- **disk-cleanup:** menu de contexto (clique direito) no explorador: "Abrir no gerenciador de arquivos", "Copiar caminho", "Ignorar este diretório", "Mover para a lixeira".

### 10.15 Checkboxes

- Seleção de uma ou mais opções de uma lista; sub-seleções com checkbox pai (estado indeterminado); em desktop, também para ligar e desligar um item. Use checkbox (e não switch) quando há várias opções relacionadas. Tokens: 18dp, state layer 40dp.
- **Flutter:** `Checkbox(tristate: true)`, `CheckboxListTile`.
- **disk-cleanup:** seleção de itens a limpar (com checkbox pai "Selecionar tudo" por categoria).

### 10.16 Switches

- Liga ou desliga **uma** opção com efeito imediato; itens independentes. Não use para opções opostas (use button group / segmented). Se a lista tem várias opções relacionadas, use checkboxes.
- **Flutter:** `Switch`, `SwitchListTile`; `thumbIcon` para ícone no polegar.
- **disk-cleanup:** configurações de alertas ("Notificar quando o uso passar do limite", "Escanear ao iniciar").

### 10.17 Sliders

- Escolher um valor numa faixa; o valor deve ter efeito imediato; mostrar a faixa completa. Variantes standard, centered e range (Expressive acrescentou tamanhos e orientação vertical). Alternativa acessível: campo de texto ao lado, sincronizado, acessível via Tab logo após o slider.
- **Flutter:** `Slider(value:, min:, max:, divisions:, label:)`, `RangeSlider`. O flag `year2023` também está deprecado aqui (aparência 2024 com `year2023: false`).
- **disk-cleanup:** limite de alerta (%) com `divisions` de 5 em 5 e um campo numérico ao lado.

### 10.18 Segmented buttons

- Escolhas simples entre 2 e 5 itens; single-select (escolher um, alternar vistas, ordenar) ou multi-select. Não mais de 5 segmentos, sem quebra de linha, não misture só ícone com só texto, não estique até a largura total em telas grandes.
- No Expressive foi substituído pelo connected button group (indisponível no Flutter).
- **Flutter:** `SegmentedButton<T>(segments: [ButtonSegment(...)], selected: {...}, onSelectionChanged:, multiSelectionEnabled:)`.
- **disk-cleanup:** alternar vista "Lista / Treemap" ou unidade "GB / GiB"; ordenar por "Tamanho / Data / Nome".

### 10.19 Tooltips

- Plain: rotular botões só com ícone. Rich: informação extra e ações sobre um recurso. Não esconda informação crítica num tooltip. Não use rich persistente em icon buttons. Plain: `inverse-surface`, `corner-extra-small`; rich: `surface-container`, level2, `corner-medium`.
- **Flutter:** `Tooltip(message:)` ou o parâmetro `tooltip` de `IconButton`/`FloatingActionButton`.
- **disk-cleanup:** obrigatório em todo icon button (desktop tem hover).

### 10.20 Search

- Navegar pelo produto com consultas; search bar com ícone, hint e ícones trailing opcionais; sugestões ou resultados em lista abaixo. Search app bar como ponto de entrada global; search icon button quando a busca é secundária. Ao focar: layout **docked** em medium e expanded; full-screen em compact. Não coloque search bar `surface-container-high` sobre fundo `surface-container` (use papéis com mais de um passo de distância). Tokens: 56dp de altura, `surface-container-high`, `corner-full`, level3.
- **Flutter:** `SearchAnchor(builder:, suggestionsBuilder:)`, `SearchAnchor.bar(...)`, `SearchBar`, `SearchController`; `isFullScreen: false` para docked.
- **disk-cleanup:** busca por caminho ou nome no explorador e nos diretórios mapeados.

### 10.21 Resumo: tela do disk-cleanup → componentes

| Tela | Componentes principais (Flutter) |
|---|---|
| Dashboard (resumo + alerta) | `NavigationRail`, `MaterialBanner` (alerta), `Card.filled` (uso do disco com medidor próprio e `displaySmall` para o número), `FloatingActionButton.extended` ("Escanear") |
| Maiores consumidores | `ListView` + `ListTile` (tamanho no trailing), `SegmentedButton` (ordenação), `MenuAnchor` (contexto) |
| Diretórios mapeados | List-detail com pane fixo 360/412dp, `SearchAnchor.bar`, `IconButton` com `tooltip` |
| Explorador de arquivos grandes | Tabela própria sobre `ListView.builder`, `FilterChip`s, `Checkbox` com pai tristate, `FilledButton` "Mover para a lixeira" |
| Limpeza (caches, lixeira, builds) | `Card.outlined` por categoria, `CheckboxListTile`, `LinearProgressIndicator`, `SnackBar` com "Desfazer" ou `AlertDialog` para irreversível |
| Limpeza de Docker | Igual à anterior, sempre com `AlertDialog` de confirmação (prune é irreversível) |
| Configurações de alertas | `SwitchListTile`, `Slider` + campo numérico, `InputChip`s para exclusões |

---

## 11. Ações destrutivas, confirmação e feedback

### 11.1 Escolha do componente pela importância

| Componente | Importância | Ação necessária |
|---|---|---|
| Snackbar | Baixa | Opcional; pode não ter botão e pode sumir sozinha |
| Banner (Flutter `MaterialBanner`; fora do M3 atual) | Média e persistente | Ação do usuário para dispensar |
| Dialog | Alta | Obrigatória; bloqueia o conteúdo até a confirmação |

### 11.2 Padrão para o disk-cleanup

1. **Ação reversível** (mover para a lixeira, ignorar diretório): execute direto, **sem dialog**, e mostre `SnackBar` "12 itens movidos para a lixeira (3,4 GB)" com a ação **"Desfazer"**. Como há ação, a snackbar persiste até interação (padrão do Flutter).
2. **Ação irreversível** (esvaziar lixeira, excluir permanentemente, `docker system prune`, limpar caches de build): **basic dialog de confirmação** antes de executar.
3. **Feedback de processo:** progress indicator determinado durante a limpeza; ao fim, snackbar com o total liberado (sem ação, pode sumir após 4 a 10 s).
4. **Falha:** snackbar se for pontual e recuperável ("Não foi possível remover 2 arquivos. Ver detalhes" com uma ação); dialog se bloquear o fluxo.

### 11.3 Regras oficiais do dialog de confirmação

- O propósito deve ficar claro pela headline e pelos botões. Headline curta, afirmação ou pergunta clara. **Evite** desculpas ("Desculpe a interrupção"), alarme ("Atenção!") e ambiguidade ("Tem certeza?").
- No máximo **duas ações**: uma de confirmação e uma de dispensa. Com uma só ação, ela deve ser de reconhecimento.
- Botões alinhados à borda trailing; **a confirmação fica sempre mais perto da borda** (à direita em LTR); a dispensa à esquerda dela. Empilhados: confirmação acima.
- Desabilite a confirmação até que uma escolha seja feita (quando houver escolha); **ações de dispensa nunca são desabilitadas**.
- Não ofereça escolhas confusas (ex.: "Cancelar" quando nada está sendo proposto).
- Ao fechar um full-screen dialog com alterações não salvas, mostre um basic dialog para confirmar o descarte.
- Acessibilidade: foco vai para o dialog ao abrir; ao fechar, volta ao elemento que o abriu; o rótulo acessível é a headline; na web, o papel é `alertdialog`. Headlines devem caber em 4 linhas com texto a 200%.

Exemplo (Flutter):

```dart
final confirmed = await showDialog<bool>(
  context: context,
  builder: (context) => AlertDialog(
    icon: const Icon(Icons.delete_forever),
    title: const Text('Excluir 4,2 GB permanentemente?'),
    content: const Text(
      'Os 318 arquivos da lixeira serão apagados e não poderão ser recuperados.',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Cancelar'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, true),
        child: const Text('Excluir'),
      ),
    ],
  ),
);
```

Os exemplos oficiais de dialog usam text buttons para as ações. Usar `error` na cor do botão de confirmação destrutiva é prática comum, mas **não confirmada** como regra do M3; se adotada, aplique `foregroundColor: colorScheme.error` de forma consistente.

---

## 12. Acessibilidade

- **Contraste de cor:**
  - Os papéis "on-*" garantem legibilidade quando pareados corretamente; o algoritmo garante ao menos 3:1 entre container e rótulo de botão.
  - Elementos não textuais agrupados (grupo de botões) precisam de **3:1** entre container e fundo. Elementos isolados e proeminentes (FAB) não precisam.
  - `outline-variant` só serve como borda de alvos se o conteúdo interno tiver **4.5:1**.
  - O Material se baseia na WCAG; para texto, a referência é WCAG 1.4.3 (4.5:1 para texto normal, 3:1 para texto grande).
  - Badges com cores customizadas: mínimo 3:1.
- **Alvos:**
  - Toque: mínimo **48x48dp** (o ícone pode ter 24dp; o padding completa o alvo).
  - Ponteiro (mouse, caneta): mínimo **44x44dp**.
  - Espaçamento entre alvos: **8dp** ou mais.
  - Densidade alta não pode reduzir alvos abaixo de 48x48dp; controles de configuração de densidade usam o tamanho padrão.
- **Foco e teclado:**
  - Tab avança, Shift+Tab volta, setas navegam dentro de componentes, Enter ativa, Esc fecha.
  - Ordem de foco segue a ordem do conteúdo (esquerda para direita, cima para baixo); defina o foco inicial de cada tela e de componentes complexos (dialog, card complexo).
  - Indicador de foco visível (tokens: 3dp de espessura, offset externo 2dp).
  - Atalhos de teclado são recomendados em apps desktop.
- **Texto:** suporte a texto em 200% sem quebrar o espaçamento.
- **Snackbars:** anúncio polite, sem roubar foco, sem prender foco.
- **Flutter:** `Semantics`, `semanticLabel` em `Icon`, `tooltip` em icon buttons, `FocusTraversalGroup`, `Shortcuts`/`Actions`, `MediaQuery.textScalerOf`. `ThemeData.materialTapTargetSize` (no desktop o padrão pode ser `shrinkWrap`; verificar se os alvos ficam com 44dp no mínimo) **(não confirmado o padrão no Linux)**.

---

## 13. Material Symbols (ícones)

### 13.1 Estilos e eixos

- Três estilos: **Outlined** (traço leve, bom para UIs densas), **Rounded** (combina com marcas de tipografia mais pesada e formas curvas) e **Sharp** (cantos retos, legível em tamanhos pequenos).
- Mais de 2.500 glifos numa única fonte variável. Os Material Icons legados continuam disponíveis, mas sem os eixos variáveis.

| Eixo | Tag | Faixa | Padrão | Uso |
|---|---|---|---|---|
| Fill | `FILL` | 0 a 1 | 0 | Estado preenchido; animar transições de estado (ex.: selecionado) |
| Weight | `wght` | 100 (thin) a 700 (bold) | 400 | Espessura do traço; combine com o peso da tipografia |
| Grade | `GRAD` | -50 a 200 (faixa da URL oficial de exemplo; exemplos citados: -25 e 200) | 0 | Ajuste fino de espessura: -25 reduz brilho de ícone claro em fundo escuro; 200 dá ênfase |
| Optical size | `opsz` | 20 a 48dp | 24 | Ajusta o traço conforme o tamanho |

Tamanhos: padrão 24dp (área útil 20x20dp com 2dp de padding); 20dp para desktop e layouts densos; 40 e 48dp para uso com display ou headline.

Toggle: use o estilo outlined para não selecionado e filled para selecionado.

### 13.2 Uso na web (protótipo)

```html
<link rel="stylesheet"
  href="https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined:opsz,wght,FILL,GRAD@20..48,100..700,0..1,-50..200&display=block">
```

```css
.material-symbols-outlined {
  font-variation-settings: 'FILL' 0, 'wght' 400, 'GRAD' 0, 'opsz' 24;
}
```

A documentação recomenda `&display=block` (evita mostrar a ligadura em texto antes de a fonte carregar) e restringir eixos e ícones (`&icon_names=...`) para reduzir o payload (exemplo oficial: 7,9 MB com todos os eixos contra 2,6 KB com subconjunto).

### 13.3 Flutter

- `Icons.*` do Flutter usa a fonte **Material Icons** (legada), não a Material Symbols. A página do Google Fonts diz que o suporte oficial a Flutter está "planejado".
- O widget `Icon` já aceita `fill`, `weight`, `grade` e `opticalSize`, mas esses eixos só têm efeito com uma fonte variável. Para usar Material Symbols: empacotar a fonte variável como asset e criar `IconData` próprios, ou usar um pacote da comunidade (ex.: `material_symbols_icons`) **(não confirmado como recomendação oficial)**.
- Também é possível definir os eixos globalmente via `IconThemeData(fill:, weight:, grade:, opticalSize:)` **(não confirmado nesta pesquisa)**.

### 13.4 Ícones úteis para o disk-cleanup

Todos os nomes abaixo existem em `Icons.*` do Flutter (conferido em `icons.dart`), exceto onde indicado.

| Contexto | Ícones |
|---|---|
| Disco e uso | `storage`, `sd_storage`, `disc_full`, `data_usage`, `pie_chart`, `donut_large`, `bar_chart`, `analytics`, `memory`; `hard_drive`, `hard_drive_2` e `database` **não existem em `Icons`** (existência na Material Symbols não confirmada) |
| Exclusão e limpeza | `delete`, `delete_outline`, `delete_forever`, `delete_sweep`, `auto_delete`, `cleaning_services`, `recycling`, `restore_from_trash`, `undo` |
| Pastas e arquivos | `folder`, `folder_open`, `folder_zip`, `drive_file_move`, `archive`, `inventory_2`, `open_in_new` |
| Builds e Docker | `build`, `terminal`, `layers` |
| Alertas e status | `warning`, `warning_amber`, `error`, `info`, `check_circle`, `notifications`, `block` |
| Navegação e ações | `dashboard`, `search`, `filter_list`, `sort`, `tune`, `settings`, `refresh`, `more_vert`, `history`, `schedule`, `visibility_off` |

---

## 14. Mapeamento de tokens para Flutter (ThemeData e ThemeExtension)

### 14.1 Tabela de correspondência

| Token M3 / CSS | Flutter |
|---|---|
| `--md-sys-color-<role>` | `ColorScheme.<roleCamelCase>` (ex.: `surfaceContainerHigh`, `onPrimaryContainer`, `outlineVariant`, `inverseSurface`, `onInverseSurface`, `inversePrimary`, `primaryFixedDim`, `onPrimaryFixedVariant`) |
| `--md-sys-color-inverse-on-surface` | `ColorScheme.onInverseSurface` (ordem invertida no nome) |
| `--md-sys-color-background` / `on-background` / `surface-variant` | Deprecados: use `surface` / `onSurface` / `surfaceContainerHighest` |
| `--md-sys-typescale-<role>-<size>-*` | `TextTheme.<roleSize>` (ex.: `titleMedium`) com `fontSize`, `height` (= line-height / size), `fontWeight`, `letterSpacing` |
| `--md-ref-typeface-brand` / `plain` | `ThemeData.fontFamily` ou `TextTheme.apply(fontFamily:)`; para typefaces distintos, ajuste os estilos display/headline/title-large separadamente |
| `--md-sys-shape-corner-*` | Sem equivalente de sistema; `ThemeExtension` própria + temas por componente (`cardTheme`, `dialogTheme`, `filledButtonTheme` …) |
| `--md-sys-elevation-level*` | `elevation: double` em dp (0, 1, 3, 6, 8, 12); recomenda-se `ThemeExtension` ou constantes |
| `--md-sys-motion-duration-*` | `Durations.short1` … `Durations.extralong4` |
| `--md-sys-motion-easing-*` | `Easing.standard`, `Easing.emphasizedDecelerate` …; emphasized = `Curves.easeInOutCubicEmphasized` |
| `--md-sys-state-*-state-layer-opacity` | Constantes usadas em `WidgetStateProperty` (`overlayColor`) |
| Breakpoints | Função própria sobre `MediaQuery.sizeOf(context).width` |
| Cores customizadas (warning, success) | `ThemeExtension` com quarteto de papéis por cor |

### 14.2 ThemeExtension para o que o ThemeData não cobre

`ThemeExtension<T>` é a interface oficial para adições ao `ThemeData` ("Typically used for custom colors"): crie a subclasse, defina os campos e implemente `copyWith` e `lerp` (o `lerp` garante transição suave ao trocar de tema).

```dart
@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
  });

  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;

  @override
  StatusColors copyWith({
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
  }) =>
      StatusColors(
        warning: warning ?? this.warning,
        onWarning: onWarning ?? this.onWarning,
        warningContainer: warningContainer ?? this.warningContainer,
        onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      );

  @override
  StatusColors lerp(StatusColors? other, double t) {
    if (other == null) return this;
    return StatusColors(
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      warningContainer: Color.lerp(warningContainer, other.warningContainer, t)!,
      onWarningContainer:
          Color.lerp(onWarningContainer, other.onWarningContainer, t)!,
    );
  }
}

@immutable
class ShapeScale extends ThemeExtension<ShapeScale> {
  const ShapeScale({
    this.none = 0,
    this.extraSmall = 4,
    this.small = 8,
    this.medium = 12,
    this.large = 16,
    this.extraLarge = 28,
  });

  final double none, extraSmall, small, medium, large, extraLarge;

  @override
  ShapeScale copyWith() => this;

  @override
  ShapeScale lerp(ShapeScale? other, double t) => this;
}
```

Montagem do tema:

```dart
ThemeData buildTheme(Brightness brightness, Color seed) {
  final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
  return ThemeData(
    colorScheme: scheme,
    extensions: [
      const ShapeScale(),
      brightness == Brightness.light ? lightStatusColors : darkStatusColors,
    ],
  );
}

final status = Theme.of(context).extension<StatusColors>()!;
```

Os valores de `lightStatusColors` e `darkStatusColors` devem sair do Material Theme Builder (custom color harmonizada) para ficarem coerentes com a source color. Os nomes `CardThemeData`/`DialogThemeData` são os atuais no Flutter recente **(não confirmado para 3.47 especificamente)**.

---

## 15. Tabela final de tokens de referência (CSS)

Valores do baseline (tokens oficiais, material-web `tokens/versions/latest`). Nomes CSS seguem a convenção do material-web: `md.sys.color.primary` → `--md-sys-color-primary`. Unidades em `px` para o protótipo (1dp = 1px CSS).

### 15.1 Cores (light em `:root`, dark em `[data-theme="dark"]` ou `prefers-color-scheme`)

```css
:root {
  --md-sys-color-primary: #6750A4;
  --md-sys-color-on-primary: #FFFFFF;
  --md-sys-color-primary-container: #EADDFF;
  --md-sys-color-on-primary-container: #4F378B;
  --md-sys-color-inverse-primary: #D0BCFF;
  --md-sys-color-secondary: #625B71;
  --md-sys-color-on-secondary: #FFFFFF;
  --md-sys-color-secondary-container: #E8DEF8;
  --md-sys-color-on-secondary-container: #4A4458;
  --md-sys-color-tertiary: #7D5260;
  --md-sys-color-on-tertiary: #FFFFFF;
  --md-sys-color-tertiary-container: #FFD8E4;
  --md-sys-color-on-tertiary-container: #633B48;
  --md-sys-color-error: #B3261E;
  --md-sys-color-on-error: #FFFFFF;
  --md-sys-color-error-container: #F9DEDC;
  --md-sys-color-on-error-container: #8C1D18;
  --md-sys-color-surface: #FEF7FF;
  --md-sys-color-on-surface: #1D1B20;
  --md-sys-color-surface-variant: #E7E0EC;
  --md-sys-color-on-surface-variant: #49454F;
  --md-sys-color-surface-dim: #DED8E1;
  --md-sys-color-surface-bright: #FEF7FF;
  --md-sys-color-surface-container-lowest: #FFFFFF;
  --md-sys-color-surface-container-low: #F7F2FA;
  --md-sys-color-surface-container: #F3EDF7;
  --md-sys-color-surface-container-high: #ECE6F0;
  --md-sys-color-surface-container-highest: #E6E0E9;
  --md-sys-color-inverse-surface: #322F35;
  --md-sys-color-inverse-on-surface: #F5EFF7;
  --md-sys-color-outline: #79747E;
  --md-sys-color-outline-variant: #CAC4D0;
  --md-sys-color-background: #FEF7FF;
  --md-sys-color-on-background: #1D1B20;
  --md-sys-color-scrim: #000000;
  --md-sys-color-shadow: #000000;
  --md-sys-color-surface-tint: #6750A4;
}

@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    --md-sys-color-primary: #D0BCFF;
    --md-sys-color-on-primary: #381E72;
    --md-sys-color-primary-container: #4F378B;
    --md-sys-color-on-primary-container: #EADDFF;
    --md-sys-color-inverse-primary: #6750A4;
    --md-sys-color-secondary: #CCC2DC;
    --md-sys-color-on-secondary: #332D41;
    --md-sys-color-secondary-container: #4A4458;
    --md-sys-color-on-secondary-container: #E8DEF8;
    --md-sys-color-tertiary: #EFB8C8;
    --md-sys-color-on-tertiary: #492532;
    --md-sys-color-tertiary-container: #633B48;
    --md-sys-color-on-tertiary-container: #FFD8E4;
    --md-sys-color-error: #F2B8B5;
    --md-sys-color-on-error: #601410;
    --md-sys-color-error-container: #8C1D18;
    --md-sys-color-on-error-container: #F9DEDC;
    --md-sys-color-surface: #141218;
    --md-sys-color-on-surface: #E6E0E9;
    --md-sys-color-surface-variant: #49454F;
    --md-sys-color-on-surface-variant: #CAC4D0;
    --md-sys-color-surface-dim: #141218;
    --md-sys-color-surface-bright: #3B383E;
    --md-sys-color-surface-container-lowest: #0F0D13;
    --md-sys-color-surface-container-low: #1D1B20;
    --md-sys-color-surface-container: #211F26;
    --md-sys-color-surface-container-high: #2B2930;
    --md-sys-color-surface-container-highest: #36343B;
    --md-sys-color-inverse-surface: #E6E0E9;
    --md-sys-color-inverse-on-surface: #322F35;
    --md-sys-color-outline: #938F99;
    --md-sys-color-outline-variant: #49454F;
    --md-sys-color-background: #141218;
    --md-sys-color-on-background: #E6E0E9;
    --md-sys-color-surface-tint: #D0BCFF;
  }
}
```

Para o seletor manual, repita o bloco dark em `:root[data-theme="dark"]`.

### 15.2 Tipografia

| Token | Valor |
|---|---|
| `--md-ref-typeface-brand` | `Roboto` |
| `--md-ref-typeface-plain` | `Roboto` |
| `--md-ref-typeface-weight-regular` / `-medium` / `-bold` | 400 / 500 / 700 |
| `--md-sys-typescale-display-large-size` / `-line-height` / `-weight` / `-tracking` | 57px / 64px / 400 / -0.25px |
| `--md-sys-typescale-display-medium-*` | 45px / 52px / 400 / 0 |
| `--md-sys-typescale-display-small-*` | 36px / 44px / 400 / 0 |
| `--md-sys-typescale-headline-large-*` | 32px / 40px / 400 / 0 |
| `--md-sys-typescale-headline-medium-*` | 28px / 36px / 400 / 0 |
| `--md-sys-typescale-headline-small-*` | 24px / 32px / 400 / 0 |
| `--md-sys-typescale-title-large-*` | 22px / 28px / 400 / 0 |
| `--md-sys-typescale-title-medium-*` | 16px / 24px / 500 / 0.15px |
| `--md-sys-typescale-title-small-*` | 14px / 20px / 500 / 0.1px |
| `--md-sys-typescale-body-large-*` | 16px / 24px / 400 / 0.5px |
| `--md-sys-typescale-body-medium-*` | 14px / 20px / 400 / 0.25px |
| `--md-sys-typescale-body-small-*` | 12px / 16px / 400 / 0.4px |
| `--md-sys-typescale-label-large-*` | 14px / 20px / 500 / 0.1px |
| `--md-sys-typescale-label-medium-*` | 12px / 16px / 500 / 0.5px |
| `--md-sys-typescale-label-small-*` | 11px / 16px / 500 / 0.5px |
| `--md-sys-typescale-<role>-<size>-font` | `var(--md-ref-typeface-brand)` para display, headline e title-large; `var(--md-ref-typeface-plain)` para os demais |

### 15.3 Shape

| Token | Valor |
|---|---|
| `--md-sys-shape-corner-none` | 0px |
| `--md-sys-shape-corner-extra-small` | 4px |
| `--md-sys-shape-corner-extra-small-top` | 4px 4px 0 0 |
| `--md-sys-shape-corner-small` | 8px |
| `--md-sys-shape-corner-medium` | 12px |
| `--md-sys-shape-corner-large` | 16px |
| `--md-sys-shape-corner-large-top` | 16px 16px 0 0 |
| `--md-sys-shape-corner-large-start` | 16px 0 0 16px |
| `--md-sys-shape-corner-large-end` | 0 16px 16px 0 |
| `--md-sys-shape-corner-large-increased` | 20px (Expressive) |
| `--md-sys-shape-corner-extra-large` | 28px |
| `--md-sys-shape-corner-extra-large-top` | 28px 28px 0 0 |
| `--md-sys-shape-corner-extra-large-increased` | 32px (Expressive) |
| `--md-sys-shape-corner-extra-extra-large` | 48px (Expressive) |
| `--md-sys-shape-corner-full` | 9999px |

### 15.4 Elevation

| Token | Valor |
|---|---|
| `--md-sys-elevation-level0` | 0px |
| `--md-sys-elevation-level1` | 1px |
| `--md-sys-elevation-level2` | 3px |
| `--md-sys-elevation-level3` | 6px |
| `--md-sys-elevation-level4` | 8px |
| `--md-sys-elevation-level5` | 12px |

Os tokens definem só a distância no eixo z; "cada plataforma determina as sombras". Para o protótipo, a sombra CSS de cada nível precisa ser definida localmente **(valores de `box-shadow` oficiais não confirmados)**. Prefira diferenciar superfícies por `surface-container-*`.

### 15.5 Motion

| Token | Valor |
|---|---|
| `--md-sys-motion-duration-short1` … `short4` | 50ms, 100ms, 150ms, 200ms |
| `--md-sys-motion-duration-medium1` … `medium4` | 250ms, 300ms, 350ms, 400ms |
| `--md-sys-motion-duration-long1` … `long4` | 450ms, 500ms, 550ms, 600ms |
| `--md-sys-motion-duration-extra-long1` … `extra-long4` | 700ms, 800ms, 900ms, 1000ms |
| `--md-sys-motion-easing-emphasized` | `cubic-bezier(0.2, 0, 0, 1)` (aproximação usada pelo material-web; a curva real é um path) |
| `--md-sys-motion-easing-emphasized-decelerate` | `cubic-bezier(0.05, 0.7, 0.1, 1)` |
| `--md-sys-motion-easing-emphasized-accelerate` | `cubic-bezier(0.3, 0, 0.8, 0.15)` |
| `--md-sys-motion-easing-standard` | `cubic-bezier(0.2, 0, 0, 1)` |
| `--md-sys-motion-easing-standard-decelerate` | `cubic-bezier(0, 0, 0, 1)` |
| `--md-sys-motion-easing-standard-accelerate` | `cubic-bezier(0.3, 0, 1, 1)` |
| `--md-sys-motion-easing-linear` | `cubic-bezier(0, 0, 1, 1)` |
| `--md-sys-motion-easing-legacy` | `cubic-bezier(0.4, 0, 0.2, 1)` |
| `--md-sys-motion-easing-legacy-decelerate` | `cubic-bezier(0, 0, 0.2, 1)` |
| `--md-sys-motion-easing-legacy-accelerate` | `cubic-bezier(0.4, 0, 1, 1)` |

### 15.6 State

| Token | Valor |
|---|---|
| `--md-sys-state-hover-state-layer-opacity` | 0.08 |
| `--md-sys-state-focus-state-layer-opacity` | 0.10 |
| `--md-sys-state-pressed-state-layer-opacity` | 0.10 |
| `--md-sys-state-dragged-state-layer-opacity` | 0.16 |
| `--md-sys-state-disabled-state-layer-opacity` | 0.38 |
| `--md-sys-state-focus-indicator-thickness` | 3px |
| `--md-sys-state-focus-indicator-outer-offset` | 2px |
| `--md-sys-state-focus-indicator-inner-offset` | -3px |

### 15.7 Layout (não são tokens `md.sys` oficiais; valores da especificação de breakpoints)

| Nome sugerido | Valor |
|---|---|
| `--app-breakpoint-medium` | 600px |
| `--app-breakpoint-expanded` | 840px |
| `--app-breakpoint-large` | 1200px |
| `--app-breakpoint-extra-large` | 1600px |
| `--app-margin-compact` | 16px |
| `--app-margin` (medium em diante) | 24px |
| `--app-pane-spacer` | 24px |
| `--app-pane-fixed-expanded` | 360px |
| `--app-pane-fixed-large` | 412px |
| `--app-space-unit` | 8px |
| `--app-target-min` | 48px |

---

## 16. Fontes

Páginas do m3.material.io (o site é renderizado no cliente; o conteúdo foi lido pelo endpoint JSON que o próprio site usa, `https://m3.material.io/_dsm/content/m3/2026-10-13_06-10-19/<id>.json`, a partir das rotas declaradas no bundle do site):

- https://m3.material.io/sitemap.xml
- https://m3.material.io/styles/color/system
- https://m3.material.io/styles/color/roles
- https://m3.material.io/styles/color/choosing-a-scheme
- https://m3.material.io/styles/color/static
- https://m3.material.io/styles/color/dynamic
- https://m3.material.io/styles/typography
- https://m3.material.io/styles/shape
- https://m3.material.io/styles/elevation
- https://m3.material.io/styles/motion/easing-and-duration
- https://m3.material.io/styles/icons
- https://m3.material.io/styles/spacing
- https://m3.material.io/foundations/layout/breakpoints
- https://m3.material.io/foundations/layout/grids-spacing
- https://m3.material.io/foundations/layout/scaffold
- https://m3.material.io/foundations/interaction/states
- https://m3.material.io/foundations/designing
- https://m3.material.io/foundations/building-for-all
- https://m3.material.io/foundations/design-tokens
- https://m3.material.io/develop/flutter
- https://m3.material.io/components/all-buttons
- https://m3.material.io/components/buttons
- https://m3.material.io/components/floating-action-button
- https://m3.material.io/components/icon-buttons
- https://m3.material.io/components/segmented-buttons
- https://m3.material.io/components/cards
- https://m3.material.io/components/chips
- https://m3.material.io/components/lists
- https://m3.material.io/components/navigation-rail
- https://m3.material.io/components/navigation-drawer
- https://m3.material.io/components/app-bars
- https://m3.material.io/components/progress-indicators
- https://m3.material.io/components/loading-indicator
- https://m3.material.io/components/badges
- https://m3.material.io/components/menus
- https://m3.material.io/components/checkbox
- https://m3.material.io/components/switch
- https://m3.material.io/components/sliders
- https://m3.material.io/components/tooltips
- https://m3.material.io/components/search
- https://m3.material.io/components/dialogs
- https://m3.material.io/components/snackbar

Material Web (tokens e documentação):

- https://github.com/material-components/material-web/blob/main/docs/theming/README.md
- https://raw.githubusercontent.com/material-components/material-web/main/README.md
- https://raw.githubusercontent.com/material-components/material-web/main/docs/theming/color.md
- https://raw.githubusercontent.com/material-components/material-web/main/docs/theming/typography.md
- https://raw.githubusercontent.com/material-components/material-web/main/tokens/versions/latest/sass/_md-sys-color.scss
- https://raw.githubusercontent.com/material-components/material-web/main/tokens/versions/latest/sass/_md-sys-color__dark.scss
- https://raw.githubusercontent.com/material-components/material-web/main/tokens/versions/latest/sass/_md-ref-palette.scss
- https://raw.githubusercontent.com/material-components/material-web/main/tokens/versions/latest/sass/_md-ref-typeface.scss
- https://raw.githubusercontent.com/material-components/material-web/main/tokens/versions/latest/sass/_md-sys-typescale.scss
- https://raw.githubusercontent.com/material-components/material-web/main/tokens/versions/latest/sass/_md-sys-shape.scss
- https://raw.githubusercontent.com/material-components/material-web/main/tokens/versions/latest/sass/_md-sys-elevation.scss
- https://raw.githubusercontent.com/material-components/material-web/main/tokens/versions/latest/sass/_md-sys-motion.scss
- https://raw.githubusercontent.com/material-components/material-web/main/tokens/versions/latest/sass/_md-sys-state.scss
- https://raw.githubusercontent.com/material-components/material-web/main/tokens/versions/latest/sass/_md-sys-state-focus-indicator.scss
- https://raw.githubusercontent.com/material-components/material-web/main/tokens/versions/v0_192/_md-sys-state.scss
- https://raw.githubusercontent.com/material-components/material-web/main/tokens/versions/v0_192/_md-sys-elevation.scss
- Tokens de componente em `https://raw.githubusercontent.com/material-components/material-web/main/tokens/versions/latest/sass/_md-comp-<componente>.scss` (elevated-card, filled-card, outlined-card, dialog, full-screen-dialog, fab-primary, extended-fab-primary, filled-button, filled-tonal-button, outlined-button, text-button, elevated-button, assist-chip, filter-chip, input-chip, menu, snackbar, navigation-drawer, navigation-rail, navigation-bar, plain-tooltip, rich-tooltip, search-bar, search-view, filled-text-field, outlined-text-field, list, switch, checkbox, badge, linear-progress-indicator, circular-progress-indicator, slider, icon-button, filled-icon-button, primary-navigation-tab)

Material Color Utilities e Theme Builder:

- https://raw.githubusercontent.com/material-foundation/material-color-utilities/main/README.md
- https://raw.githubusercontent.com/material-foundation/material-color-utilities/main/concepts/color_spaces.md
- https://raw.githubusercontent.com/material-foundation/material-color-utilities/main/typescript/scheme/scheme_tonal_spot.ts
- https://raw.githubusercontent.com/material-foundation/material-color-utilities/main/typescript/dynamiccolor/variant.ts
- https://material-foundation.github.io/material-theme-builder/

Flutter (API e código-fonte):

- https://api.flutter.dev/flutter/material/ColorScheme/ColorScheme.fromSeed.html
- https://api.flutter.dev/flutter/material/ColorScheme-class.html
- https://api.flutter.dev/flutter/material/DynamicSchemeVariant.html
- https://api.flutter.dev/flutter/material/ThemeData-class.html
- https://api.flutter.dev/flutter/material/ThemeData/useMaterial3.html
- https://api.flutter.dev/flutter/material/ThemeExtension-class.html
- https://api.flutter.dev/flutter/material/TextTheme-class.html
- https://api.flutter.dev/flutter/material/Easing-class.html
- https://api.flutter.dev/flutter/material/Durations-class.html
- https://api.flutter.dev/flutter/material/NavigationRail-class.html
- https://api.flutter.dev/flutter/material/NavigationDrawer-class.html
- https://api.flutter.dev/flutter/material/NavigationBar-class.html
- https://api.flutter.dev/flutter/material/Card-class.html
- https://api.flutter.dev/flutter/material/FilledButton-class.html
- https://api.flutter.dev/flutter/material/FloatingActionButton-class.html
- https://api.flutter.dev/flutter/material/IconButton-class.html
- https://api.flutter.dev/flutter/material/FilterChip-class.html
- https://api.flutter.dev/flutter/material/ActionChip-class.html
- https://api.flutter.dev/flutter/material/InputChip-class.html
- https://api.flutter.dev/flutter/material/LinearProgressIndicator-class.html
- https://api.flutter.dev/flutter/material/CircularProgressIndicator-class.html
- https://api.flutter.dev/flutter/material/AlertDialog-class.html
- https://api.flutter.dev/flutter/material/Dialog-class.html
- https://api.flutter.dev/flutter/material/SnackBar-class.html
- https://api.flutter.dev/flutter/material/MaterialBanner-class.html
- https://api.flutter.dev/flutter/material/Badge-class.html
- https://api.flutter.dev/flutter/material/MenuAnchor-class.html
- https://api.flutter.dev/flutter/material/SegmentedButton-class.html
- https://api.flutter.dev/flutter/material/SearchAnchor-class.html
- https://api.flutter.dev/flutter/material/DataTable-class.html
- https://api.flutter.dev/flutter/material/Tooltip-class.html
- https://api.flutter.dev/flutter/material/Switch-class.html
- https://api.flutter.dev/flutter/material/Slider-class.html
- https://api.flutter.dev/flutter/widgets/Icon-class.html
- https://raw.githubusercontent.com/flutter/flutter/master/packages/flutter/lib/src/material/typography.dart
- https://raw.githubusercontent.com/flutter/flutter/master/packages/flutter/lib/src/material/theme_data.dart
- https://raw.githubusercontent.com/flutter/flutter/master/packages/flutter/lib/src/material/motion.dart
- https://raw.githubusercontent.com/flutter/flutter/master/packages/flutter/lib/src/animation/curves.dart
- https://raw.githubusercontent.com/flutter/flutter/master/packages/flutter/lib/src/material/filled_button.dart
- https://raw.githubusercontent.com/flutter/flutter/master/packages/flutter/lib/src/material/snack_bar.dart
- https://raw.githubusercontent.com/flutter/flutter/master/packages/flutter/lib/src/material/badge.dart
- https://raw.githubusercontent.com/flutter/flutter/master/packages/flutter/lib/src/material/icons.dart

Outras fontes oficiais do Google:

- https://developer.android.com/develop/ui/views/layout/use-window-size-classes
- https://developers.google.com/fonts/docs/material_symbols

Observação: o código-fonte do Flutter foi lido do branch `master`, e as páginas do api.flutter.dev refletem a versão publicada no momento da consulta. Pequenas diferenças em relação ao Flutter 3.47 stable são possíveis; confira os pontos marcados como "(não confirmado)" contra a versão instalada no projeto.
