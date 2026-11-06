# disk-cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Construir o disk-cleanup, gerenciador de espaço em disco para desktop Linux em Flutter, e publicá-lo como AppImage num GitHub Release com página no GitHub Pages.

**Architecture:** Serviços em Dart puro (sem Flutter) fazem medição, varredura e exclusão. Todo acesso ao sistema passa por uma abstração `ProcessRunner` (`du`, `find`, `df`, `docker`, `pkexec`), o que torna os serviços testáveis com um runner falso. Um `ScanController` e um `CleanupController` (`ChangeNotifier`) orquestram os serviços. A UI Material 3 lê esses controllers e segue o protótipo aprovado e o design system. O empacotamento usa `flutter build linux` + appimagetool em GitHub Actions (ubuntu-22.04).

**Tech Stack:** Flutter 3.47.5 / Dart 3, `window_manager`, `material_symbols_icons`, `path`, `flutter_test`. GNU coreutils/findutils (`du`, `find`, `df`), `pkexec`, `gio`, Docker CLI. appimagetool, GitHub Actions, GitHub Pages.

**Spec:** `docs/superpowers/specs/2026-11-06-disk-cleanup-design.md`. Referências visuais e de comportamento: `docs/design-system.md`, `docs/design-system/tokens.css` e o protótipo https://claude.ai/artifact/2LoQMkHSnNJfSs2kiMSrL3. Leia a spec antes de qualquer task de UI.

## Global Constraints

- Flutter fora do PATH: todo comando começa com `export PATH="$HOME/flutter/bin:$PATH"`.
- Plataforma: Linux x86_64, Ubuntu 22.04+ (glibc 2.35). Só o target `linux` no projeto Flutter.
- Interface 100% em português brasileiro, com acentuação correta. Sem travessões (—) em textos da UI.
- Unidades decimais: 1 GB = 10⁹ bytes, 1 casa decimal, vírgula decimal, unidade sempre visível ("44,0 GB"). O tooltip mostra os bytes exatos.
- Limiares padrão: atenção abaixo de 15% **ou** 20 GB livres; crítico abaixo de 5% **ou** 5 GB. Vale o que acontecer primeiro.
- Toda exclusão passa pelo `CleanupConfirmDialog`. Nada é apagado sem confirmação.
- Pré-seleção: só itens `RiskLevel.safe` com `requiresRoot == false`. Também ficam desmarcados builds de projetos modificados nos últimos 14 dias (com "Proteger projetos ativos" ligado) e caches de apps em execução.
- Root: um único `pkexec /bin/sh -c '<script>'` por lote. O script é montado só a partir das classes `RootCommand` (Task 12), com argumentos validados por regex. Texto digitado pelo usuário nunca entra no script, e nada de dentro do AppImage roda como root.
- Varredura sem seguir symlinks e sem atravessar pontos de montagem (`du -x`, `find -xdev`). Saídas de `du` e `find` são lidas separadas por NUL.
- Tamanho mínimo da janela: 720 × 560. A janela lembra tamanho, posição e estado maximizado.
- Faixas de largura: menor que 840 dp, rail compacto de 80 dp; de 840 a 1199 dp, rail estendido de 220 dp; 1200 dp ou mais, list-detail em Diretórios com pane de 412 dp e conteúdo limitado a 1200 dp nas outras telas.
- Cores, tipografia e componentes: `docs/design-system.md` e os hex de `docs/design-system/tokens.css`. Seed `#006A6A`; os hex são copiados, não regerados. Fontes: Roboto e Roboto Mono embutidas. Ícones: Material Symbols Rounded.
- Comentários no código só quando forem indispensáveis (invariante não óbvia). Commits sem trailer `Co-Authored-By`.
- Nenhum teste apaga, move ou escreve fora de um `Directory.systemTemp.createTemp()`. Nenhum teste chama `pkexec`, `docker` ou `sudo` reais.
- Arquivos do app: configurações em `~/.config/disk-cleanup/settings.json`; snapshots em `~/.local/share/disk-cleanup/snapshots/`.

## Review Focus

1. **Caminhos com espaço, colchete, aspas, acento ou quebra de linha** (`~/Local Sites`, `Dispatch [BASE][…].nsz`): precisam aparecer certos e ser apagados certos. Testes nas Tasks 6, 9 e 11.
2. **Symlinks** (`node_modules` do pnpm, link apontando para fora do home): a varredura não segue o link, e apagar remove o link, nunca o alvo. Testes nas Tasks 8 e 11.
3. **Pasta sem permissão no meio da varredura:** o `du` sai com código 1 e saída parcial. O resultado parcial é usado, o erro é contado e nada trava. Testes nas Tasks 6 e 14.
4. **Senha cancelada ou errada no pkexec** (exit 126/127): o lote vira "cancelado", nenhum item é dado como apagado e os itens continuam na lista. Testes nas Tasks 12 e 15.
5. **Item mudou entre a varredura e a confirmação** (pasta já apagada, projeto voltou a ser ativo, Docker parado): revalidar antes de apagar; caminho ausente é "ignorado", não erro; Docker indisponível mostra estado vazio. Testes nas Tasks 13 e 15.

---

## Estrutura de arquivos

```
pubspec.yaml · analysis_options.yaml · LICENSE (MIT) · README.md
assets/fonts/            Roboto-{Regular,Medium,Bold}.ttf, RobotoMono-{Regular,Medium}.ttf, OFL.txt
lib/main.dart            bootstrap: window_manager, Services, runApp
lib/app.dart             DiskCleanupApp (MaterialApp + tema + AppShell)
lib/services.dart        Services: cria e injeta serviços e controllers
lib/core/format.dart             formatBytes, formatBytesExact, formatAgo
lib/core/process_runner.dart     ProcessRunner, SystemProcessRunner, RunResult, CancelToken
lib/core/models.dart             RiskLevel, CleanupCategory, CleanupItem, CleanupAction
lib/settings/settings.dart       Settings, BuildRule, WindowBounds (JSON)
lib/settings/settings_store.dart SettingsStore
lib/disk/disk_info.dart          VolumeUsage, parseDf, DiskInfoService
lib/disk/alert.dart              AlertLevel, evaluateAlert
lib/scan/du_scanner.dart         DuScanner, DuResult, DirEntrySize
lib/scan/snapshot_store.dart     SnapshotStore, Snapshot, weeklyDelta
lib/scan/build_finder.dart       BuildFinder, BuildArtifact
lib/scan/large_files.dart        LargeFileFinder, LargeFile
lib/scan/cache_catalog.dart      CacheDef, kCacheCatalog, CacheInventory, SystemInventory
lib/scan/preselect.dart          shouldPreselect, composeConsumers, Consumer
lib/scan/scan_controller.dart    ScanController, ScanState, ScanProgressInfo
lib/cleanup/trash_service.dart   TrashService, TrashedEntry
lib/cleanup/safe_deleter.dart    SafeDeleter, DeleteOutcome
lib/cleanup/privileged_runner.dart RootCommand (+ subclasses), buildRootScript, PrivilegedRunner
lib/cleanup/docker_service.dart  DockerService, DockerInventory, parseDockerSize
lib/cleanup/cleanup_controller.dart CleanupController, CleanupResult
lib/ui/theme/…           color_schemes.dart, severity_colors.dart, app_theme.dart
lib/ui/shell/…           responsive.dart, app_shell.dart
lib/ui/widgets/…         um arquivo por componente do design system (Tasks 16 e 17)
lib/ui/pages/…           overview, cleanup, docker, large_files, directories, settings
test/support/fake_process_runner.dart
packaging/appimage/      AppRun, disk-cleanup.desktop, disk-cleanup.svg, build_appimage.sh
.github/workflows/       release.yml, pages.yml
site/                    index.html, app.js, tokens.css
```

---

### Task 1: Projeto Flutter, tema e fontes

**Files:**
- Create: `pubspec.yaml`, `analysis_options.yaml`, `lib/main.dart`, `lib/app.dart`, `lib/ui/theme/color_schemes.dart`, `lib/ui/theme/severity_colors.dart`, `lib/ui/theme/app_theme.dart`, `assets/fonts/*`
- Modify: `.gitignore` (acrescentar o padrão Flutter mantendo `!/docs/`)
- Test: `test/ui/theme/app_theme_test.dart`

**Interfaces:**
- Produces: `ThemeData buildTheme(Brightness b)`; `class SeverityColors extends ThemeExtension<SeverityColors>` com `success`, `onSuccess`, `successContainer`, `onSuccessContainer`, `warning`, `onWarning`, `warningContainer`, `onWarningContainer` (crítico usa `ColorScheme.error*`); `const lightScheme`, `const darkScheme` (`ColorScheme`).

- [ ] **Step 1:** `flutter create --platforms=linux --org br.com.uesleinasch --project-name disk_cleanup .` na raiz do repo. Mantenha `docs/` e o `.gitignore` com `!/docs/` no fim. Adicione as dependências `window_manager`, `material_symbols_icons` e `path`. Baixe Roboto (400, 500, 700) e Roboto Mono (400, 500) estáticas do Google Fonts para `assets/fonts/`, com `OFL.txt`, e declare as famílias `Roboto` e `RobotoMono` no pubspec.
- [ ] **Step 2: Teste que falha**

```dart
test('tema claro usa os hex do tokens.css', () {
  final t = buildTheme(Brightness.light);
  expect(t.useMaterial3, isTrue);
  expect(t.colorScheme.primary, const Color(0xFF006A6A));
  expect(t.colorScheme.surface, const Color(0xFFF4FBFA));
  expect(t.extension<SeverityColors>()!.warning, const Color(0xFF775A00));
  expect(t.textTheme.bodyMedium!.fontFamily, 'Roboto');
});
test('tema escuro', () {
  final t = buildTheme(Brightness.dark);
  expect(t.colorScheme.primary, const Color(0xFF80D5D4));
  expect(t.extension<SeverityColors>()!.success, const Color(0xFF76DAA1));
});
```

- [ ] **Step 3:** Rode `flutter test test/ui/theme/app_theme_test.dart`. Esperado: FAIL (`buildTheme` não existe).
- [ ] **Step 4:** Implemente os três arquivos de tema. Copie **todos** os roles claro/escuro de `docs/design-system/tokens.css` (`--md-sys-color-*` para `ColorScheme`, `--dc-color-success/warning*` para `SeverityColors`). Siga o mapeamento Flutter do design system (seção "Mapeamento para Flutter"), com `VisualDensity.compact` em listas. `DiskCleanupApp` em `app.dart` usa `buildTheme` nos dois brilhos e `themeMode: ThemeMode.system`, por enquanto com um `Scaffold` vazio.
- [ ] **Step 5:** Rode o teste (PASS), depois `flutter analyze` (sem issues) e `flutter build linux --debug` (sucesso).
- [ ] **Step 6:** Commit `feat: projeto Flutter com tema Material 3 e fontes`.

### Task 2: Shell responsivo e janela

**Files:**
- Create: `lib/ui/shell/responsive.dart`, `lib/ui/shell/app_shell.dart`, `lib/ui/pages/placeholder_page.dart` (temporário, removido na Task 23), `test/support/test_app.dart` (`Widget testApp(Widget child, {Brightness brightness = Brightness.light})`, que envolve o widget em `MaterialApp(theme: buildTheme(...), home: Scaffold(body: child))`)
- Modify: `lib/main.dart`, `lib/app.dart`
- Test: `test/ui/shell/app_shell_test.dart`

**Interfaces:**
- Produces: `enum WidthClass { compact, medium, expanded, large }` e `WidthClass widthClassOf(double width)`, com limites `<840` compact/medium (rail compacto), `840..1199` expanded e `>=1200` large; `enum AppDestination { overview, directories, largeFiles, cleanup, docker, settings }`; `AppShell({required AppDestination current, required ValueChanged<AppDestination> onSelect, required AlertLevel alert, required Widget body})`.
- Consumes: `AlertLevel` (Task 5). Crie o enum já agora em `lib/disk/alert.dart`, só com `ok, warning, critical`.

- [ ] **Step 1: Teste que falha**

```dart
testWidgets('rail compacto abaixo de 840', (t) async {
  t.view.physicalSize = const Size(800, 600); t.view.devicePixelRatio = 1;
  await t.pumpWidget(testApp(AppShell(current: AppDestination.overview, onSelect: (_) {}, alert: AlertLevel.ok, body: const SizedBox())));
  expect(t.widget<NavigationRail>(find.byType(NavigationRail)).extended, isFalse);
});
testWidgets('rail estendido a partir de 840, com os seis destinos em pt-BR', (t) async {
  t.view.physicalSize = const Size(1000, 700); t.view.devicePixelRatio = 1;
  // pump igual ao anterior
  expect(t.widget<NavigationRail>(find.byType(NavigationRail)).extended, isTrue);
  for (final l in ['Visão geral', 'Diretórios', 'Arquivos grandes', 'Limpeza', 'Docker', 'Configurações']) {
    expect(find.text(l), findsOneWidget);
  }
});
testWidgets('badge de alerta no destino Visão geral', (t) async {
  // alert: AlertLevel.warning → find.bySemanticsLabel('Espaço em disco: atenção') encontra 1
});
```

- [ ] **Step 2:** Rode o teste. Esperado: FAIL.
- [ ] **Step 3:** Implemente o `AppShell` com `NavigationRail`, usando os ícones e rótulos do protótipo (`space_dashboard`, `folder_special`, `description`, `cleaning_services`, `deployed_code`, `settings`, todos rounded, com `FILL 1` no selecionado). Atalhos `Ctrl+1` a `Ctrl+6` e `Ctrl+,` via `Shortcuts`/`Actions`. Em `main.dart`, o `window_manager` aplica `minimumSize: Size(720, 560)` e tamanho inicial 1280 × 800. Lembrar a geometria da janela fica para a Task 4, porque depende do `SettingsStore`.
- [ ] **Step 4:** Rode o teste (PASS) e `flutter analyze`.
- [ ] **Step 5:** Commit `feat: shell com navigation rail responsivo`.

### Task 3: Núcleo (formatação, ProcessRunner e modelos)

**Files:**
- Create: `lib/core/format.dart`, `lib/core/process_runner.dart`, `lib/core/models.dart`, `test/support/fake_process_runner.dart`
- Test: `test/core/format_test.dart`, `test/core/process_runner_test.dart`

**Interfaces:**
- Produces:
  - `String formatBytes(int bytes)`, `String formatBytesExact(int bytes)`, `String formatAgo(DateTime then, DateTime now)`.
  - `class RunResult { final int exitCode; final List<int> stdout; final String stderr; String get stdoutText; }`.
  - `class CancelToken { void cancel(); bool get isCancelled; }`.
  - `abstract class ProcessRunner { Future<RunResult> run(String executable, List<String> args, {CancelToken? cancel}); }`.
  - `class SystemProcessRunner implements ProcessRunner`: `Process.start` sem shell, mata o processo quando `cancel` dispara e lança `ScanCancelled`. Um `ProcessException` (binário ausente) vira `RunResult(exitCode: 127)`.
  - `class FakeProcessRunner implements ProcessRunner`: `when(String exe, List<String> args, RunResult r)`, com comparação exata dos argumentos, e `calls` (lista de `[exe, ...args]`).
  - Modelos:
    - `enum RiskLevel { safe, attention, danger }`, na ordem de gravidade;
    - `enum CleanupCategory { trash, cache, build, system, docker, largeFile }`;
    - `sealed class CleanupAction`, com as variantes `DeletePathsAction(List<String> paths)`, `TrashPathsAction(List<String> paths)`, `EmptyTrashAction()`, `RootAction(List<RootCommand> commands)` e `DockerAction(DockerOp op, List<String> ids)`;
    - `enum DockerOp { inventory, pruneBuildCache, removeContainers, removeImages, removeVolumes }`;
    - `class CleanupItem { String id; CleanupCategory category; String title; String? path; String note; int bytes; RiskLevel risk; bool requiresRoot; bool preselected; DateTime? lastModified; CleanupAction action; }`, com `toJson`/`fromJson`.

  `RootCommand` é declarado na Task 12. Por enquanto, crie em `privileged_runner.dart` só `sealed class RootCommand {}`, que a Task 12 completa.

- [ ] **Step 1: Testes que falham**

```dart
expect(formatBytes(44000000000), '44,0 GB');
expect(formatBytes(502500000000), '502,5 GB');
expect(formatBytes(999), '999 B');
expect(formatBytes(1500000), '1,5 MB');
expect(formatBytes(1250000000000), '1,3 TB');
expect(formatBytesExact(44000000000), '44.000.000.000 bytes');
final now = DateTime(2026, 11, 6, 12);
expect(formatAgo(now.subtract(const Duration(seconds: 20)), now), 'agora');
expect(formatAgo(now.subtract(const Duration(minutes: 3)), now), 'há 3 min');
expect(formatAgo(now.subtract(const Duration(days: 1)), now), 'ontem');
expect(formatAgo(now.subtract(const Duration(days: 95)), now), 'há 3 meses');
expect(formatAgo(now.subtract(const Duration(days: 400)), now), 'há 1 ano');
```

Mais: `SystemProcessRunner` rodando `sleep 5` com um `CancelToken` cancelado após 100 ms lança `ScanCancelled` em menos de 1 s; e rodar `binario-que-nao-existe` retorna `exitCode` 127.
- [ ] **Step 2:** Rode. Esperado: FAIL.
- [ ] **Step 3:** Implemente.
- [ ] **Step 4:** Rode `flutter test test/core`. Esperado: PASS.
- [ ] **Step 5:** Commit `feat: formatação, process runner e modelos`.

### Task 4: Configurações e geometria da janela

**Files:**
- Create: `lib/settings/settings.dart`, `lib/settings/settings_store.dart`
- Modify: `lib/main.dart` (salvar e restaurar a geometria)
- Test: `test/settings/settings_test.dart`

**Interfaces:**
- Produces:
  - `class BuildRule { final String dirName; final String marker; bool matchesMarker(String fileName); }`. O `marker` é um nome exato ou um glob com `*`.
  - `class WindowBounds { double x, y, width, height; bool maximized; }`.
  - `class Settings`, com os campos:
    - `mappedDirs` (`List<String>`);
    - `warnPercent` = 15, `warnBytes` = 20000000000, `critPercent` = 5, `critBytes` = 5000000000;
    - `protectActiveProjects` = true, `activeProjectDays` = 14;
    - `buildRules` (`List<BuildRule>`);
    - `themeMode` (`ThemeMode`), `bannerSnoozedUntil` (`DateTime?`), `window` (`WindowBounds?`).

    Métodos: `Settings.defaults(String home)`, `copyWith`, `toJson`/`fromJson`.
  - `class SettingsStore { SettingsStore(String filePath); Future<Settings> load(String home); Future<void> save(Settings s); }`. O `load` devolve os padrões quando o arquivo falta ou está corrompido, e o arquivo corrompido é renomeado para `.bak`.
  - `const kDefaultBuildRules`, com os pares:
    - `node_modules` + `package.json`;
    - `.angular` + `angular.json`;
    - `target` + `Cargo.toml`;
    - `.stack-work` + `stack.yaml`;
    - `dist-newstyle` + `*.cabal`;
    - `build` + `pubspec.yaml`, `build` + `build.gradle`, `build` + `build.gradle.kts`;
    - `.dart_tool` + `pubspec.yaml`;
    - `bin` + `*.csproj`, `obj` + `*.csproj`.

- [ ] **Step 1: Testes que falham**
  - `Settings.defaults('/home/u').mappedDirs == ['/home/u']`, e os limiares são exatamente os valores acima.
  - Um ciclo `toJson` → `fromJson` preserva todos os campos.
  - `BuildRule('bin','*.csproj').matchesMarker('Api.csproj')` é true; com `'Api.cs'` é false.
  - `SettingsStore.load` com o arquivo inexistente devolve os padrões.
  - Com JSON inválido, devolve os padrões e cria `settings.json.bak`.
  - `save` seguido de `load` devolve o mesmo valor.
- [ ] **Step 2:** Rode. Esperado: FAIL.
- [ ] **Step 3:** Implemente. Em `main.dart`, restaure `settings.window` (inclusive `maximized`) antes de mostrar a janela, e salve com debounce de 500 ms em `onWindowResized/Moved/Maximize/Unmaximize` via `WindowListener`.
- [ ] **Step 4:** Rode os testes (PASS).
- [ ] **Step 5:** Commit `feat: configurações persistentes e geometria da janela`.

### Task 5: Uso do disco e nível de alerta

**Files:**
- Create: `lib/disk/disk_info.dart`
- Modify: `lib/disk/alert.dart`
- Test: `test/disk/disk_info_test.dart`, `test/disk/alert_test.dart`

**Interfaces:**
- Produces:
  - `class VolumeUsage { String device, fsType, mountPoint; int size, used, available; int get reserved; double get freeFraction; }`.
  - `List<VolumeUsage> parseDf(String output)`.
  - `class DiskInfoService { DiskInfoService(ProcessRunner r); Future<List<VolumeUsage>> volumes(); }`. Roda `df -B1 --output=source,fstype,size,used,avail,target -x tmpfs -x devtmpfs -x squashfs -x overlay -x efivarfs`.
  - `AlertLevel evaluateAlert(VolumeUsage v, Settings s)`.

- [ ] **Step 1: Testes que falham**
  - `parseDf` com cabeçalho e duas linhas, uma delas com ponto de montagem `/media/u/Meu Disco` (com espaço), devolve 2 volumes. O `mountPoint` sai certo, e `reserved == size - used - available`.
  - `evaluateAlert`, com os padrões:
    - 44,0e9 livres de 502,5e9 dá `warning` (8,8%);
    - 4,6e9 de 502,5e9 dá `critical`;
    - 128,3e9 de 502,5e9 dá `ok`;
    - 25e9 de 1000e9 dá `critical` (2,5% vence os 25 GB);
    - 18e9 de 100e9 dá `warning` (18% está acima de 15%, mas fica abaixo de 20 GB).
- [ ] **Step 2:** Rode. Esperado: FAIL.
- [ ] **Step 3:** Implemente. No parse, os 5 primeiros campos são separados por espaço e o resto da linha é o `target`.
- [ ] **Step 4:** Rode (PASS).
- [ ] **Step 5:** Commit `feat: leitura do df e avaliação de alerta`.

### Task 6: DuScanner

**Files:**
- Create: `lib/scan/du_scanner.dart`
- Test: `test/scan/du_scanner_test.dart`

**Interfaces:**
- Consumes: `ProcessRunner`, `CancelToken`.
- Produces:
  - `class DirEntrySize { String path; int bytes; }`.
  - `class DuResult { List<DirEntrySize> entries; int total; int errors; bool permissionDenied; }`.
  - `class DuScanner`, com construtor `DuScanner(ProcessRunner r)` e os métodos:
    - `Future<DuResult> childrenSizes(String dir, {CancelToken? cancel})`, que roda `du -x -a -d1 -B1 -0 <dir>`;
    - `Future<Map<String,int>> sizesOf(List<String> paths, {CancelToken? cancel})`, que roda `du -sx -B1 -0 <paths…>` e omite caminhos ausentes.

- [ ] **Step 1: Testes que falham (FakeProcessRunner)**
  - Uma saída `"1000\t/h/a b\x00" "2000\t/h/Dispatch [BASE].nsz\x00" "3000\t/h\x00"` com exit 0 dá entradas `/h/a b` (1000) e `/h/Dispatch [BASE].nsz` (2000), mais `total == 3000`. O próprio diretório fica fora de `entries`.
  - Exit 1 com stderr `du: cannot read directory '/h/x': Permission denied` e saída parcial dá entradas parseadas, `errors == 1` e `permissionDenied` falso, porque `/h` foi lido.
  - Exit 1 sem nenhuma linha do próprio `dir` e stderr com `Permission denied` em `dir` dá `permissionDenied == true` e `total == 0`.
  - Um `CancelToken` já cancelado faz `childrenSizes` lançar `ScanCancelled`.
  - Teste de integração com `SystemProcessRunner` em diretório temporário: arquivos `x\ny.bin` (com quebra de linha no nome, 10 bytes) e `acentuação.txt` aparecem com os nomes exatos.
- [ ] **Step 2:** Rode. Esperado: FAIL.
- [ ] **Step 3:** Implemente: decodifique os bytes como UTF-8 com `allowMalformed` e quebre por `\x00`.
- [ ] **Step 4:** Rode (PASS).
- [ ] **Step 5:** Commit `feat: medição de diretórios via du`.

### Task 7: Snapshots e variação semanal

**Files:**
- Create: `lib/scan/snapshot_store.dart`
- Test: `test/scan/snapshot_store_test.dart`

**Interfaces:**
- Produces:
  - `class Snapshot { DateTime takenAt; Map<String,dynamic> state; }`. O `state` é o `ScanState.toJson()` da Task 14; aqui ele é opaco.
  - `class SnapshotStore`, com construtor `SnapshotStore(String dir)` e os métodos:
    - `Future<void> save(Snapshot s)`, que grava `snapshot-<epochMs>.json`;
    - `Future<Snapshot?> latest()`;
    - `Future<Snapshot?> closestTo(DateTime target, {Duration tolerance = const Duration(days: 3)})`;
    - `Future<void> prune({Duration keep = const Duration(days: 90)})`.
  - `int? weeklyDelta(int currentBytes, int? weekAgoBytes)`.

- [ ] **Step 1: Testes que falham**
  - Com snapshots de 10, 7 e 1 dia atrás, `closestTo(now - 7d)` devolve o de 7 dias.
  - Só com um snapshot de 1 dia atrás, `closestTo(now - 7d)` devolve null (fora da tolerância).
  - `latest` devolve o mais recente.
  - `prune` remove os mais velhos que 90 dias.
  - Um arquivo corrompido é ignorado, sem lançar exceção.
  - `weeklyDelta(61200, 59100) == 2100` e `weeklyDelta(1, null) == null`.
- [ ] **Step 2:** Rode. Esperado: FAIL.
- [ ] **Step 3:** Implemente.
- [ ] **Step 4:** Rode (PASS).
- [ ] **Step 5:** Commit `feat: snapshots de varredura`.

### Task 8: BuildFinder

**Files:**
- Create: `lib/scan/build_finder.dart`
- Test: `test/scan/build_finder_test.dart`

**Interfaces:**
- Consumes: `ProcessRunner`, `DuScanner.sizesOf`, `BuildRule`.
- Produces: `class BuildArtifact { String path; String projectDir; BuildRule rule; int bytes; DateTime projectModified; }` e `class BuildFinder { BuildFinder(ProcessRunner r, DuScanner du); Future<List<BuildArtifact>> find(List<String> roots, List<BuildRule> rules, {List<String> excludeRoots = const [], CancelToken? cancel}); }`.

- [ ] **Step 1: Testes de integração que falham** (`SystemProcessRunner` em diretório temporário)
  - `proj/package.json` com `proj/node_modules/a.js` é detectado.
  - `solto/node_modules` sem `package.json` **não** é detectado.
  - `proj/node_modules/dep/node_modules` não aparece separado, porque a busca faz prune.
  - `app/build` com `app/pubspec.yaml` é detectado; `foo/build` sem marcador não é.
  - `api/bin` com `api/Api.csproj` é detectado.
  - `link_nm -> /algum/lugar` (symlink chamado `node_modules` ao lado de um `package.json`) **não** é detectado.
  - Um caminho dentro de `excludeRoots` (por exemplo a lixeira) é ignorado.
  - `projectModified` é o maior mtime entre os filhos diretos de `projectDir`, sem contar as próprias pastas de build. Para testar, use `File.setLastModified`.
- [ ] **Step 2:** Rode. Esperado: FAIL.
- [ ] **Step 3:** Implemente com `find <roots> -xdev ( -path <exclude> -prune ) -o -type d ( -name n1 -o -name n2 … ) -prune -print0`. Valide o marcador em Dart com `BuildRule.matchesMarker` sobre a listagem do diretório pai. Meça os tamanhos com uma única chamada `sizesOf`.
- [ ] **Step 4:** Rode (PASS).
- [ ] **Step 5:** Commit `feat: detecção de artefatos de build com marcador`.

### Task 9: LargeFileFinder

**Files:**
- Create: `lib/scan/large_files.dart`
- Test: `test/scan/large_files_test.dart`

**Interfaces:**
- Produces: `class LargeFile { String path; int bytes; DateTime lastAccess; DateTime modified; }` e `class LargeFileFinder { LargeFileFinder(ProcessRunner r); Future<List<LargeFile>> find(List<String> roots, {int minBytes = 1000000000, List<String> excludeRoots = const [], CancelToken? cancel}); }`. O resultado vem ordenado por `bytes` decrescente.

- [ ] **Step 1: Testes que falham**
  - Com o FakeProcessRunner, a saída `"6700000000\t1730000000.5\t1730000000.0\t/h/Downloads/Dispatch [BASE][01008BA02525A000][v0].nsz\x00"` dá um `LargeFile` com o caminho exato e as datas convertidas.
  - Com o `SystemProcessRunner` e `minBytes: 1000` num diretório temporário: um arquivo de 2000 bytes chamado `vídeo com espaço.mp4` entra; um de 10 bytes não entra; um arquivo dentro de `excludeRoots` não entra.
- [ ] **Step 2:** Rode. Esperado: FAIL.
- [ ] **Step 3:** Implemente com `find <roots> -xdev ( -path <exclude> -prune ) -o -type f -size +<minBytes-1>c -printf '%s\t%A@\t%T@\t%p\0'`.
- [ ] **Step 4:** Rode (PASS).
- [ ] **Step 5:** Commit `feat: busca de arquivos grandes`.

### Task 10: Catálogo de caches e itens de sistema

**Files:**
- Create: `lib/scan/cache_catalog.dart`
- Test: `test/scan/cache_catalog_test.dart`

**Interfaces:**
- Produces:
  - `class CacheDef { String id; String title; String relPath; String note; String? processName; }`.
  - `const List<CacheDef> kCacheCatalog`, com os caminhos relativos ao home:

    | id | caminho | processo |
    | --- | --- | --- |
    | uv | `.cache/uv` | |
    | pip | `.cache/pip` | |
    | npm | `.npm/_cacache` | |
    | yarn | `.cache/yarn` | |
    | pnpm | `.local/share/pnpm/store` | |
    | bun | `.bun/install/cache` | |
    | gradle | `.gradle/caches` | |
    | nuget | `.nuget/packages` | |
    | pub | `.pub-cache/hosted` | |
    | cabal | `.cabal/packages` | |
    | stack | `.stack/pantry` | |
    | cargo | `.cargo/registry/cache` | |
    | chrome | `.cache/google-chrome` | `chrome` |
    | chromium | `.cache/chromium` | `chromium` |
    | brave | `.cache/BraveSoftware` | `brave` |
    | firefox | `.cache/mozilla/firefox` | `firefox` |
    | playwright | `.cache/ms-playwright` | |

    Os títulos e notas seguem o protótipo, por exemplo "Cache do uv" com a nota "Pacotes Python baixados".
  - `class CacheInventory { CacheInventory(ProcessRunner r, DuScanner du); Future<List<CleanupItem>> scan(String home); }`. Cada item sai com `category: cache`, `risk: safe`, `requiresRoot: false`, ação `DeletePathsAction([abs])` e `preselected` falso quando `pgrep -x <processName>` retorna exit 0. Caminhos ausentes são omitidos.
  - `class SystemInventory { SystemInventory(ProcessRunner r, DuScanner du); Future<List<CleanupItem>> scan(); }`. Gera:
    - **journal:** tamanho via `du` de `/var/log/journal`; ação `RootAction([JournalVacuum()])`; nota "Mantém os últimos 500 MB";
    - **apt:** tamanho de `/var/cache/apt/archives`; ação `RootAction([AptClean()])`;
    - **snap:** um item por revisão `disabled` de `snap list --all`. O tamanho vem do arquivo `/var/lib/snapd/snaps/<nome>_<rev>.snap`, e a ação é `RootAction([SnapRemoveRevision(nome, rev)])`.

    Todos saem com `category: system`, `risk: safe`, `requiresRoot: true` e `preselected: false`.

- [ ] **Step 1: Testes que falham (FakeProcessRunner)**
  - Home com `.cache/uv` e `.cache/BraveSoftware` medidos, e `pgrep -x brave` com exit 0: o item do uv sai pré-selecionado e o do Brave não, com a nota "Brave está aberto: feche para limpar".
  - Um cache ausente não gera item.
  - Uma saída de `snap list --all` com uma linha `core20  20240111  2182  latest/stable  canonical**  base,disabled` gera `SnapRemoveRevision('core20','2182')`.
  - Um `snap` inexistente (exit 127) não gera item nem erro.
- [ ] **Step 2:** Rode. Esperado: FAIL.
- [ ] **Step 3:** Implemente. Use os `RootCommand` da Task 12; se essa task ainda não existir, faça a Task 12 antes.
- [ ] **Step 4:** Rode (PASS).
- [ ] **Step 5:** Commit `feat: catálogo de caches e itens de sistema`.

### Task 11: TrashService e SafeDeleter

**Files:**
- Create: `lib/cleanup/trash_service.dart`, `lib/cleanup/safe_deleter.dart`
- Test: `test/cleanup/trash_service_test.dart`, `test/cleanup/safe_deleter_test.dart`

**Interfaces:**
- Produces:
  - `class TrashedEntry { String originalPath; String trashedName; }`.
  - `class TrashListing { String name; String originalPath; DateTime deletedAt; int bytes; }`.
  - `class TrashService`, com construtor `TrashService({required String trashDir, required ProcessRunner runner, required DuScanner du})` e os métodos:
    - `Future<TrashedEntry?> moveToTrash(String path)`;
    - `Future<void> restore(TrashedEntry e)`;
    - `Future<List<TrashListing>> list()`;
    - `Future<void> empty()`;
    - `Future<void> deleteFromTrash(List<String> names)`.
  - `enum DeleteOutcome { deleted, missing, refused, failed }`.
  - `class SafeDeleter { SafeDeleter({required List<String> allowedRoots, required List<String> protectedPaths}); Future<DeleteOutcome> delete(String path); }`.

- [ ] **Step 1: Testes que falham** (diretório temporário fazendo o papel de home e de `Trash`)
  - `moveToTrash('/tmp/x/relatório final.pdf')`:
    - cria `files/relatório final.pdf` e `info/relatório final.pdf.trashinfo`;
    - o `.trashinfo` contém `[Trash Info]`, `Path=` com o caminho percent-encoded (`relat%C3%B3rio%20final.pdf`) e `DeletionDate=` no formato `yyyy-MM-ddTHH:mm:ss`.
  - Mover dois arquivos com o mesmo nome gera nomes únicos (`nome.2.ext`).
  - `restore` devolve o arquivo ao caminho original e remove o `.trashinfo`.
  - `empty` deixa `files/` e `info/` vazios, mas existentes.
  - Quando o `rename` falha com EXDEV (simule injetando uma função de rename que lança `FileSystemException` com `osError.errorCode == 18`), o serviço chama `gio trash <path>` e retorna null.
  - `SafeDeleter`, com `allowedRoots: [tmp]` e `protectedPaths: [tmp/home]`:
    - apaga `tmp/home/proj/node_modules` → `deleted`;
    - apagar `tmp/home` → `refused`;
    - apagar `/etc` → `refused`;
    - um caminho com `..` que normaliza para fora de `allowedRoots` → `refused`;
    - um caminho inexistente → `missing`;
    - um symlink `tmp/home/link -> tmp/fora` → `deleted`, e `tmp/fora/arquivo` continua existindo.
- [ ] **Step 2:** Rode. Esperado: FAIL.
- [ ] **Step 3:** Implemente seguindo a especificação freedesktop Trash 1.0. Faça `SafeDeleter` com `FileSystemEntity.type(path, followLinks: false)`: se for link, use `Link.delete`; se não, `delete(recursive: true)`.
- [ ] **Step 4:** Rode (PASS).
- [ ] **Step 5:** Commit `feat: lixeira freedesktop e exclusão protegida`.

### Task 12: PrivilegedRunner

**Files:**
- Modify: `lib/cleanup/privileged_runner.dart`
- Test: `test/cleanup/privileged_runner_test.dart`

**Interfaces:**
- Produces:
  - `sealed class RootCommand { String toShell(); }`.
  - Subclasses de `RootCommand`:

    | Classe | Comando gerado | Validação |
    | --- | --- | --- |
    | `JournalVacuum()` | `journalctl --vacuum-size=500M` | |
    | `AptClean()` | `apt-get clean` | |
    | `SnapRemoveRevision(String name, String revision)` | `snap remove 'name' --revision='rev'` | `name` com `^[a-z0-9][a-z0-9-]*$`, `revision` com `^[0-9]+$` |
    | `DuMeasure(String path)` | `du -sx -B1 -0 'path'` | caminho absoluto, sem `'`, sem `\n`, sem segmento `..` |
    | `DockerCli(DockerOp op, List<String> ids)` | `docker system df -v --format '{{json .}}'` (`inventory`, sem ids), `docker builder prune -f`, `docker rm 'id'…`, `docker rmi 'id'…` ou `docker volume rm 'nome'…` | ids com `^[a-f0-9]{12,64}$`, volumes com `^[A-Za-z0-9][A-Za-z0-9_.-]*$` |

    Os construtores lançam `ArgumentError` quando a entrada é inválida.
  - `String buildRootScript(List<RootCommand> cmds)`. Para cada comando `i`, gera `<cmd>; echo "__dc_status <i> $?"`.
  - `class RootBatchResult { bool cancelled; Map<int,int> exitCodes; String stdout; }`.
  - `class PrivilegedRunner { PrivilegedRunner(ProcessRunner r); Future<RootBatchResult> run(List<RootCommand> cmds); }`. Executa `pkexec /bin/sh -c <script>`; exit 126 ou 127 sem nenhum `__dc_status` vira `cancelled: true`.

- [ ] **Step 1: Testes que falham**
  - `SnapRemoveRevision("core20'; rm -rf / #", '1')` lança `ArgumentError`, e `DuMeasure('relativo')` também.
  - `buildRootScript([JournalVacuum(), AptClean()])` contém exatamente uma linha por comando, com `__dc_status 0` e `__dc_status 1`.
  - Com o FakeProcessRunner, `run` chama `pkexec` com `['/bin/sh','-c', script]` uma única vez para 3 comandos.
  - Stdout `__dc_status 0 0\n__dc_status 1 1\n` dá `exitCodes == {0:0, 1:1}`.
  - Exit 126 sem status dá `cancelled == true`.
- [ ] **Step 2:** Rode. Esperado: FAIL.
- [ ] **Step 3:** Implemente.
- [ ] **Step 4:** Rode (PASS).
- [ ] **Step 5:** Commit `feat: execução root em lote via pkexec`.

### Task 13: DockerService

**Files:**
- Create: `lib/cleanup/docker_service.dart`
- Test: `test/cleanup/docker_service_test.dart`, com fixture `test/fixtures/docker_system_df_v.json` (saída real de `docker system df -v --format '{{json .}}'` capturada nesta máquina, com IDs truncados se quiser)

**Interfaces:**
- Produces:
  - Modelos:
    - `class DockerContainer { String id; String name; String image; String status; int bytes; }`;
    - `class DockerImage { String id; String repoTag; int bytes; }`;
    - `class DockerVolume { String name; int bytes; }`.
  - `class DockerInventory`, com os campos:
    - `bool available`, `bool needsRoot`;
    - `int imagesBytes`, `containersBytes`, `volumesBytes`, `buildCacheBytes`, `buildCacheReclaimable`;
    - `List<DockerContainer> stopped`, `List<DockerImage> unusedImages`, `List<DockerVolume> unusedVolumes`.

    Também `List<CleanupItem> toItems()`: o build cache sai como `safe`, pré-selecionado; containers, imagens e volumes saem como `attention`, sem pré-seleção. Títulos e notas seguem o protótipo.
  - `int parseDockerSize(String s)`, com unidades SI: `'1.2GB'` → 1200000000; `'512kB'` → 512000; `'0B'` → 0.
  - `class DockerService`, com construtor `DockerService(ProcessRunner r, PrivilegedRunner root)` e os métodos:
    - `Future<DockerInventory> inventory()`;
    - `Future<DockerInventory> inventoryAsRoot()`, que usa `DockerCli(DockerOp.inventory, [])` e só é chamado pelo botão "Ler com senha de administrador";
    - `Future<bool> execute(DockerOp op, List<String> ids)`. Quando `needsRoot`, roda via `PrivilegedRunner` com `DockerCli`.

- [ ] **Step 1: Testes que falham**
  - A fixture gera totais e listas coerentes:
    - imagens sem uso são as que têm `Containers == "0"`;
    - containers parados são os com estado `exited` ou `created`;
    - volumes sem uso são os com `Links == "0"`;
    - `buildCacheReclaimable` soma as entradas com `InUse == false`.
  - `docker` ausente (exit 127) dá `available == false`, sem exceção.
  - Exit 1 com stderr contendo `permission denied while trying to connect to the Docker daemon socket` dá `needsRoot == true` sem chamar `pkexec`.
  - Daemon parado (`Cannot connect to the Docker daemon`) dá `available == false`.
  - Todos os casos de `parseDockerSize` acima.
- [ ] **Step 2:** Rode. Esperado: FAIL.
- [ ] **Step 3:** Implemente com `docker system df -v --format '{{json .}}'` e as ações `docker builder prune -f`, `docker rm`, `docker rmi` e `docker volume rm`.
- [ ] **Step 4:** Rode (PASS).
- [ ] **Step 5:** Commit `feat: inventário e limpeza do Docker`.

### Task 14: ScanController, pré-seleção e consumidores

**Files:**
- Create: `lib/scan/preselect.dart`, `lib/scan/scan_controller.dart`, `lib/services.dart`
- Test: `test/scan/preselect_test.dart`, `test/scan/scan_controller_test.dart`

**Interfaces:**
- Consumes: todos os serviços das Tasks 4 a 13.
- Produces:
  - `bool shouldPreselect(CleanupItem item, Settings s, DateTime now, {bool appRunning = false})`.
  - `class Consumer { String label; String path; int bytes; String icon; }`.
  - `List<Consumer> composeConsumers({required String home, required Map<String, DuResult> mapped, int? dockerBytes, Map<String,int> systemDirs = const {}})`. A saída vem ordenada por `bytes` decrescente, sem caminhos repetidos.
  - `class ScanProgressInfo { String currentDir; int doneDirs; int totalDirs; bool running; }`.
  - `class ScanState`, com os campos:
    - `DateTime? updatedAt`;
    - `List<VolumeUsage> volumes`, `AlertLevel alert`;
    - `List<Consumer> consumers`, `Map<String, DuResult> mappedDirs`;
    - `Map<String, int?> weeklyDeltas`, `Set<String> lockedDirs`;
    - `List<CleanupItem> items`, `DockerInventory? docker`, `List<LargeFile> largeFiles`;
    - `ScanProgressInfo progress`.

    Métodos e getters: `toJson`/`fromJson`, `VolumeUsage? get systemVolume` (o volume de `/`), `int get safeReclaimableBytes` (soma dos itens com `preselected`) e `int get recoverableBytes` (soma dos itens `safe` + `attention`).
  - `class ScanController extends ChangeNotifier`, com os membros:
    - `ScanController(Services s)`;
    - `ScanState get state`;
    - `Future<void> loadLast()`, que mostra o último snapshot na hora;
    - `Future<void> scan()`;
    - `void cancel()`;
    - `void toggle(String itemId)`;
    - `void setSelection(CleanupCategory c, bool selected)`.
  - `class Services`, que reúne `ProcessRunner`, `SettingsStore`, todos os serviços, `home` e `now()`. O construtor `Services.system()` monta tudo com os caminhos reais.

- [ ] **Step 1: Testes que falham**
  - `shouldPreselect`:
    - um cache `safe` sem root dá true;
    - um item de sistema `requiresRoot` dá false;
    - um build com `lastModified` 3 dias atrás e `protectActiveProjects` ligado dá false;
    - o mesmo build com 30 dias dá true;
    - um item `attention` dá false;
    - `appRunning: true` dá false.
  - `composeConsumers`, com `mapped` = {`/h`: filhos `/h/ueslei` (61,2e9), `/h/trabalho` (46,2e9), `/h/.cache` (38,7e9)}, {`/h/trabalho`: total 46,2e9} e `dockerBytes` 83,8e9:
    - a ordem é Docker, ueslei, trabalho, .cache;
    - `/h/trabalho` aparece uma vez só;
    - o rótulo do Docker é "Docker" com caminho `/var/lib/docker`.
  - `ScanController.scan()` com serviços falsos:
    - termina com `progress.running == false`, `updatedAt` preenchido e um snapshot salvo;
    - `alert == AlertLevel.warning` para 44e9 livres de 502,5e9;
    - um diretório mapeado com `permissionDenied` vai para `lockedDirs`;
    - `cancel()` durante a varredura mantém o estado anterior e deixa `running` falso.
  - `loadLast()` com um snapshot salvo preenche o `state` sem chamar `du`.
- [ ] **Step 2:** Rode. Esperado: FAIL.
- [ ] **Step 3:** Implemente. Ordem da varredura:
  1. `df`;
  2. cada diretório mapeado com `childrenSizes`, atualizando o `progress` por diretório;
  3. diretórios de sistema conhecidos (`/var/lib/flatpak`, `/var/lib/snapd`, `/var/log`), também com `childrenSizes`;
  4. caches;
  5. sistema;
  6. builds nos diretórios mapeados, com `excludeRoots` = lixeira e `~/.cache`;
  7. arquivos grandes, com `excludeRoots` = lixeira;
  8. Docker;
  9. lixeira (um item `EmptyTrashAction`, `danger`, mais um item por entrada de `TrashService.list()`).

  Aplique `shouldPreselect` nos itens. Calcule `weeklyDeltas` com `closestTo(now - 7d)`. Salve o snapshot e rode `prune`.

  O `alert` é o pior nível entre o volume de `/` e os volumes que contêm algum diretório mapeado (o volume com o `mountPoint` mais longo que seja prefixo do caminho). Acrescente ao Step 1 o caso: um diretório mapeado em `/media/u/Dados` com 2% livre deixa `alert == critical` mesmo com `/` saudável.
- [ ] **Step 4:** Rode (PASS).
- [ ] **Step 5:** Commit `feat: orquestração da varredura`.

### Task 15: CleanupController

**Files:**
- Create: `lib/cleanup/cleanup_controller.dart`
- Test: `test/cleanup/cleanup_controller_test.dart`

**Interfaces:**
- Consumes: `SafeDeleter`, `TrashService`, `PrivilegedRunner`, `DockerService`, `Settings`.
- Produces:
  - `class CleanupResult { int freedBytes; int succeeded; int skipped; int failed; bool cancelled; List<TrashedEntry> undo; }`.
  - `class CleanupController { CleanupController(Services s); Future<CleanupResult> execute(List<CleanupItem> items); Future<void> undo(List<TrashedEntry> entries); }`.
  - `RiskLevel highestRisk(List<CleanupItem> items)`.
  - `bool batchNeedsRoot(List<CleanupItem> items)`.

- [ ] **Step 1: Testes que falham**
  - Um lote com 2 `DeletePathsAction` (uma pasta existe e a outra não), 1 `RootAction` com 2 comandos e 1 `DockerAction`:
    - o `pkexec` é chamado uma única vez, com os 2 comandos;
    - `skipped == 1`, que é a pasta ausente;
    - `freedBytes` soma só os itens que tiveram sucesso.
  - Com o `pkexec` cancelado (126): `cancelled == true`; os itens root contam como não feitos e o `freedBytes` deles não entra; os itens não root do mesmo lote **não** são executados. O lote é atômico do ponto de vista do usuário: cancelar a senha cancela tudo.
  - Um build cujo projeto foi modificado depois da varredura (`projectModified` agora mais novo que `activeProjectDays`) é pulado (`skipped`).
  - `TrashPathsAction` devolve as entradas em `undo`, e `undo()` restaura os arquivos.
  - `highestRisk` de safe + attention dá `attention`.
- [ ] **Step 2:** Rode. Esperado: FAIL.
- [ ] **Step 3:** Implemente. Ordem: revalidar tudo; se houver itens root, rodar o `PrivilegedRunner` primeiro (se ele for cancelado, abortar o lote); depois Docker, lixeira e exclusões.
- [ ] **Step 4:** Rode (PASS).
- [ ] **Step 5:** Commit `feat: execução de lotes de limpeza`.

### Task 16: Componentes de exibição

**Files:**
- Create: `lib/ui/widgets/disk_usage_bar.dart`, `consumer_bar_list.dart`, `alert_banner.dart`, `risk_chip.dart`, `scan_progress.dart`, `empty_state.dart`
- Test: `test/ui/widgets/display_widgets_test.dart`

**Interfaces:**
- Produces:
  - `DiskUsageBar({required int used, required int recoverable, required int reserved, required int free, required int capacity})`: os segmentos ficam em `used - recoverable`, `recoverable` (listrado), `reserved` e `free`, com legenda.
  - `ConsumerBarList({required List<Consumer> consumers, int limit = 7, VoidCallback? onSeeAll})`.
  - `AlertBanner({required AlertLevel level, required VolumeUsage volume, required int safeBytes, required VoidCallback onSnooze, required VoidCallback onShowWhatToFree})`.
  - `RiskChip({required RiskLevel level})`.
  - `RootRequiredIndicator()`.
  - `ScanProgressView({required ScanProgressInfo progress, VoidCallback? onCancel})`.
  - `EmptyState({required IconData icon, required String title, required String body, Widget? action})`.

  Visual, anatomia e semântica seguem o `docs/design-system.md` (seção 4) e o protótipo.

- [ ] **Step 1: Testes que falham**
  - `DiskUsageBar` com used 433,8e9, recoverable 84,3e9, reserved 24,7e9 e free 44e9 mostra os textos de legenda "Em uso", "349,5 GB", "Recuperável", "84,3 GB", "Reservado pelo sistema", "24,7 GB", "Livre" e "44,0 GB". O `Semantics` dela contém "44,0 GB livres de 502,5 GB".
  - `AlertBanner` em `warning` mostra "Espaço em disco baixo: restam 44,0 GB (8,8%)" e os botões "Adiar 1 dia" e "Ver o que liberar".
  - Em `critical` mostra "Disco quase cheio: restam 4,6 GB (0,9%)".
  - `RiskChip` mostra "Seguro", "Atenção" e "Perigoso", cada um com ícone e texto, nunca só cor.
  - `ConsumerBarList` com 9 itens mostra 7 e o link "Ver todos".
  - `ScanProgressView` mostra "Varrendo…" e um botão "Cancelar" que chama `onCancel`.
- [ ] **Step 2:** Rode. Esperado: FAIL.
- [ ] **Step 3:** Implemente.
- [ ] **Step 4:** Rode (PASS).
- [ ] **Step 5:** Commit `feat: componentes de exibição do design system`.

### Task 17: Componentes de limpeza (tile, barra de resumo, diálogo)

**Files:**
- Create: `lib/ui/widgets/cleanup_item_tile.dart`, `cleanup_summary_bar.dart`, `cleanup_confirm_dialog.dart`
- Test: `test/ui/widgets/cleanup_widgets_test.dart`

**Interfaces:**
- Consumes: `CleanupItem`, `highestRisk`, `batchNeedsRoot`, `RiskChip`, `RootRequiredIndicator`.
- Produces:
  - `CleanupItemTile({required CleanupItem item, required bool selected, required ValueChanged<bool> onChanged})`.
  - `CleanupSummaryBar({required int count, required int bytes, required RiskLevel risk, required VoidCallback? onClean, VoidCallback? onClearSelection, String? labelOverride})`.
  - `Future<CleanupDecision?> showCleanupConfirmDialog(BuildContext c, {required List<CleanupItem> items, bool offerPermanent = false})`, com `class CleanupDecision { bool permanent; }`. Retorna null quando o usuário cancela.

- [ ] **Step 1: Testes que falham** (textos copiados do protótipo e do design system, seção 6.4)
  - **Variante Seguro**, com 3 caches somando 38,6e9:
    - título "Limpar 38,6 GB?";
    - texto "Estes itens são recriados automaticamente quando necessário. Nenhum arquivo pessoal será apagado.";
    - botão principal `FilledButton` "Limpar 38,6 GB";
    - foco inicial em "Cancelar";
    - Esc retorna null.
  - **Variante Atenção** (containers Docker): ícone `warning` e o aviso "Dados gravados dentro dos containers e fora de volumes serão perdidos.".
  - **Variante Perigoso**:
    - esvaziar a lixeira mostra o título "Apagar 10,2 GB permanentemente?", o texto "Não há como desfazer." e o botão com cor `error`;
    - arquivos pessoais com `offerPermanent: true` mostram os rádios "Mover para a lixeira" (marcado) e "Apagar permanentemente". Escolher o segundo troca o botão para "Apagar X GB" e retorna `permanent: true`.
  - Um lote com item `requiresRoot` mostra "O sistema vai pedir sua senha de administrador para concluir.".
  - A lista do diálogo rola quando a altura é 560.
  - `CleanupSummaryBar` com `count: 0` deixa o botão desabilitado.
  - `CleanupItemTile` de um item root mostra "requer admin".
- [ ] **Step 2:** Rode. Esperado: FAIL.
- [ ] **Step 3:** Implemente. Use `AlertDialog`, largura máxima 560, `scrollable: true`. O botão destrutivo usa `FilledButton` com `ColorScheme.error`.
- [ ] **Step 4:** Rode (PASS).
- [ ] **Step 5:** Commit `feat: diálogo de confirmação e itens de limpeza`.

### Task 18: Tela Visão geral

**Files:**
- Create: `lib/ui/pages/overview_page.dart`
- Modify: `lib/app.dart` (ligar o `ScanController`, `loadLast()` e depois `scan()` na abertura)
- Test: `test/ui/pages/overview_page_test.dart`

**Interfaces:**
- Consumes: `ScanController`, `CleanupController`, `Settings`, os widgets das Tasks 16 e 17.
- Produces: `OverviewPage({required ScanController scan, required CleanupController cleanup, required SettingsController settings})`. O `SettingsController` (`ChangeNotifier` sobre `Settings` + `SettingsStore`) é criado nesta task em `lib/settings/settings_controller.dart`, com `Settings get value` e `Future<void> update(Settings Function(Settings) f)`.

- [ ] **Step 1: Testes que falham**, com `ScanState` montado igual ao protótipo (free 44e9, capacity 502,5e9, 3 itens pré-selecionados somando 84,3e9):
  - o banner de atenção aparece;
  - o card mostra "Pode liberar com segurança", "84,3 GB" e o botão "Liberar 84,3 GB com segurança";
  - tocar no botão abre o diálogo com o título "Limpar 84,3 GB?". Confirmar chama `CleanupController.execute` com os 3 itens e mostra a SnackBar "84,3 GB liberados.";
  - "Adiar 1 dia" esconde o banner e grava `bannerSnoozedUntil` no dia seguinte, enquanto o badge do rail continua;
  - com 7+ consumidores aparece "Ver todos", que navega para Diretórios;
  - com largura 720 a tela renderiza sem overflow (`tester.takeException()` é null), e o mesmo com 1600.
- [ ] **Step 2:** Rode. Esperado: FAIL.
- [ ] **Step 3:** Implemente seguindo o protótipo (artboard Visão geral), incluindo a seção "Outros volumes" com um card pequeno por volume montado que não seja `/`. Os cards usam `Wrap`/`LayoutBuilder`; o conteúdo tem largura máxima de 1200 e fica centralizado. A app bar mostra "Atualizado há X" e o botão de atualizar (`F5`/`Ctrl+R`). Durante a varredura, o `ScanProgressView` aparece sob a app bar.
- [ ] **Step 4:** Rode (PASS) e `flutter analyze`.
- [ ] **Step 5:** Commit `feat: tela Visão geral`.

### Task 19: Tela Limpeza

**Files:**
- Create: `lib/ui/pages/cleanup_page.dart`
- Test: `test/ui/pages/cleanup_page_test.dart`

**Interfaces:**
- Produces: `CleanupPage({required ScanController scan, required CleanupController cleanup})`.

- [ ] **Step 1: Testes que falham**
  - As abas "Lixeira (X GB)", "Caches (X GB)" e "Builds (X GB)" mostram o total de cada categoria (`cache` e `system` entram em Caches).
  - Na aba Caches, o item do journal mostra "requer admin" e vem desmarcado.
  - Marcar o journal e limpar abre o diálogo com o aviso de senha.
  - Na aba Lixeira, marcar todos troca o botão para "Esvaziar lixeira (X GB)", e o diálogo é o da variante Perigoso.
  - Depois de confirmar, os itens somem da lista e aparece a SnackBar "X GB liberados.".
  - Uma aba vazia mostra o `EmptyState` "Nada para limpar aqui".
  - Com largura 720 não há overflow.
- [ ] **Step 2:** Rode. Esperado: FAIL.
- [ ] **Step 3:** Implemente seguindo o protótipo (artboard Limpeza): `TabBar`, uma lista de `CleanupItemTile` e a `CleanupSummaryBar` fixa. `Ctrl+A` seleciona tudo da aba.
- [ ] **Step 4:** Rode (PASS).
- [ ] **Step 5:** Commit `feat: tela Limpeza`.

### Task 20: Tela Docker

**Files:**
- Create: `lib/ui/pages/docker_page.dart`
- Test: `test/ui/pages/docker_page_test.dart`

**Interfaces:**
- Produces: `DockerPage({required ScanController scan, required CleanupController cleanup})`.

- [ ] **Step 1: Testes que falham**
  - Os 4 cards de totais aparecem: Imagens, Containers, Volumes e Build cache.
  - Cada grupo traz o `RiskChip` (Build cache Seguro, os outros Atenção). Só o build cache vem marcado.
  - Marcar um volume e confirmar mostra o aviso "Volumes podem conter dados de banco que não existem em outro lugar.".
  - Com `available == false` aparece o `EmptyState` "Docker não encontrado".
  - Com `needsRoot` aparece o estado de permissão com o botão "Ler com senha de administrador", e o `pkexec` não é chamado sem o clique.
  - Abaixo de 840 os cards ficam em 2 colunas, sem overflow com largura 720.
- [ ] **Step 2:** Rode. Esperado: FAIL.
- [ ] **Step 3:** Implemente seguindo o protótipo (artboard Docker).
- [ ] **Step 4:** Rode (PASS).
- [ ] **Step 5:** Commit `feat: tela Docker`.

### Task 21: Tela Arquivos grandes

**Files:**
- Create: `lib/ui/pages/large_files_page.dart`
- Test: `test/ui/pages/large_files_page_test.dart`

**Interfaces:**
- Produces: `LargeFilesPage({required ScanController scan, required CleanupController cleanup})`.

- [ ] **Step 1: Testes que falham**
  - A lista vem ordenada por tamanho decrescente.
  - O chip "Compactados" filtra por `.7z`, `.zip`, `.tar*` e `.rar`. "Imagens de disco" filtra por `.img`, `.iso`, `.qcow2`, `.vdi` e `.vmdk`. "Vídeos" filtra por `.mp4`, `.mkv`, `.webm`, `.mov` e `.avi`. "Sem acesso há 6 meses" usa `lastAccess`.
  - O campo de filtro (Ctrl+F) filtra pelo nome.
  - "Mover para a lixeira" abre o diálogo Perigoso com `offerPermanent`. Confirmar com o padrão mostra a SnackBar com "Desfazer", e tocar em Desfazer restaura o item na lista.
  - `Delete` abre o diálogo com a lixeira marcada; `Shift+Delete` abre com "Apagar permanentemente" marcado.
  - Com largura 720, a coluna "Último acesso" vai para baixo do nome e não há overflow.
  - Um caminho longo é truncado no meio, com o caminho completo no tooltip.
- [ ] **Step 2:** Rode. Esperado: FAIL.
- [ ] **Step 3:** Implemente seguindo o protótipo (artboard Arquivos grandes). Use `ListView.builder` com linhas de tabela própria e o botão "Abrir local" (`xdg-open` no diretório pai).
- [ ] **Step 4:** Rode (PASS).
- [ ] **Step 5:** Commit `feat: tela Arquivos grandes`.

### Task 22: Tela Diretórios

**Files:**
- Create: `lib/ui/pages/directories_page.dart`
- Test: `test/ui/pages/directories_page_test.dart`

**Interfaces:**
- Produces: `DirectoriesPage({required ScanController scan, required SettingsController settings})`.

- [ ] **Step 1: Testes que falham**
  - Cada diretório mapeado mostra o tamanho e a variação "+2,1 GB desde a última semana". Com variação de 5 GB ou mais, o ícone `trending_up` fica na cor warning. Sem snapshot de referência aparece "Sem histórico ainda".
  - Selecionar um diretório mostra os filhos em barras.
  - Um diretório em `lockedDirs` mostra "Precisa de senha de administrador para medir" e o botão "Medir com senha de administrador", que chama o `PrivilegedRunner` com `DuMeasure`.
  - "Adicionar diretório" abre o diálogo com o campo de caminho e o seletor (`zenity --file-selection --directory` via `ProcessRunner`; se o zenity faltar, sobra só o campo). "Adicionar e medir" grava em `mappedDirs` e mede o diretório. Um caminho inexistente mostra o erro "Esse diretório não existe".
  - "Parar de mapear" remove o diretório de `mappedDirs` e mostra a SnackBar "Não apaga nada".
  - Em 1280 de largura a tela é list-detail lado a lado; em 1000 é lista e o detalhe abre por navegação com botão voltar.
- [ ] **Step 2:** Rode. Esperado: FAIL.
- [ ] **Step 3:** Implemente seguindo o protótipo (artboard Diretórios).
- [ ] **Step 4:** Rode (PASS).
- [ ] **Step 5:** Commit `feat: tela Diretórios`.

### Task 23: Tela Configurações e integração final

**Files:**
- Create: `lib/ui/pages/settings_page.dart`
- Modify: `lib/app.dart` (todas as páginas no lugar do placeholder; `themeMode` vem do `SettingsController`), `docs/design-system.md` (alinhar às divergências listadas na spec, seção 5)
- Delete: `lib/ui/pages/placeholder_page.dart`
- Test: `test/ui/pages/settings_page_test.dart`, `test/app_test.dart`

**Interfaces:**
- Produces: `SettingsPage({required SettingsController settings})`.

- [ ] **Step 1: Testes que falham**
  - Os sliders de atenção (5 a 40%) e crítico (1 a 15%) gravam `warnPercent` e `critPercent`. O crítico não pode ficar maior ou igual ao de atenção: o slider trava 1 ponto abaixo.
  - O switch "Proteger projetos ativos" grava o valor.
  - Adicionar uma regra de build exige nome **e** marcador; o botão fica desabilitado sem marcador. Remover uma regra funciona.
  - O seletor de tema Sistema/Claro/Escuro troca o `themeMode` do `MaterialApp`.
  - "Sobre" mostra a versão vinda do pubspec e a nota "Tamanhos em GB decimais (1 GB = 1.000.000.000 bytes); o df -h mostra GiB."
  - Em `app_test`: o app sobe com serviços falsos e navega pelos 6 destinos com `Ctrl+1` a `Ctrl+6` sem exceção, em 720 × 560 e em 1920 × 1080.
- [ ] **Step 2:** Rode. Esperado: FAIL.
- [ ] **Step 3:** Implemente. Atualize o `design-system.md` nos pontos: janela mínima 720 × 560, "pastas de busca" igual a diretórios mapeados, atalho da Visão geral abrindo o diálogo direto, itens root sem pré-seleção e uma senha por lote.
- [ ] **Step 4:** Rode `flutter test` (a suíte inteira passa) e `flutter analyze` (sem issues).
- [ ] **Step 5:** Rode `flutter run -d linux` e peça ao usuário para validar visualmente: as seis telas, maximizar e restaurar, redimensionar até 720 × 560 e o tema escuro. A validação visual é dele; não automatize o navegador nem tire screenshots.
- [ ] **Step 6:** Commit `feat: tela Configurações e integração das telas`.

### Task 24: Empacotamento AppImage

**Files:**
- Create: `packaging/appimage/AppRun`, `packaging/appimage/disk-cleanup.desktop`, `packaging/appimage/disk-cleanup.svg`, `packaging/appimage/build_appimage.sh`
- Test: o próprio script, verificado no Step 3

**Interfaces:**
- Produces: `packaging/appimage/build_appimage.sh <versão>`, que gera `dist/disk-cleanup-<versão>-x86_64.AppImage`.

- [ ] **Step 1:** Crie o `.desktop` (`Name=disk-cleanup`, `Comment=Gerenciador de espaço em disco`, `Categories=System;Utility;`, `Icon=disk-cleanup`, `Exec=disk-cleanup`). O SVG reproduz o símbolo `data_usage` em `#006A6A` sobre fundo `#F4FBFA`, com cantos arredondados. O `AppRun` faz `exec "$HERE/disk-cleanup" "$@"`, com `LD_LIBRARY_PATH="$HERE/lib"`.
- [ ] **Step 2:** O script:
  1. roda `flutter build linux --release`;
  2. copia `build/linux/x64/release/bundle/*` para `AppDir/`;
  3. copia AppRun, `.desktop` e ícone;
  4. baixa o appimagetool (release `continuous` do `AppImage/appimagetool`) para `.cache/` se ainda não tiver;
  5. roda `ARCH=x86_64 appimagetool AppDir dist/disk-cleanup-$1-x86_64.AppImage`.

  O script usa `set -euo pipefail`.
- [ ] **Step 3:** Rode `packaging/appimage/build_appimage.sh 0.1.0-dev` e depois `./dist/disk-cleanup-0.1.0-dev-x86_64.AppImage`. Esperado: a janela abre. Peça ao usuário para confirmar visualmente. Acrescente `dist/` e `AppDir/` ao `.gitignore`.
- [ ] **Step 4:** Commit `build: empacotamento AppImage`.

### Task 25: Repositório público, CI de release e GitHub Pages

**Files:**
- Create: `README.md`, `LICENSE` (MIT, "Ueslei Nascimento", 2026), `.github/workflows/release.yml`, `.github/workflows/pages.yml`, `site/index.html`, `site/app.js`, `site/tokens.css` (cópia de `docs/design-system/tokens.css`)

**Interfaces:**
- Consumes: `packaging/appimage/build_appimage.sh`.
- Produces: o workflow de release, disparado em push de tag `v*`; o workflow de Pages, disparado em push na `main` que mexa em `site/**` e por `workflow_dispatch`.

- [ ] **Step 1:** README em pt-BR com:
  - o que o app faz e um link para a página;
  - instalação: baixar o AppImage, `chmod +x` e executar;
  - requisitos: Ubuntu 22.04+, `libfuse2` ou `--appimage-extract-and-run`;
  - como desenvolver (`flutter run -d linux`, `flutter test`);
  - licença.
- [ ] **Step 2:** `release.yml`:
  - roda em `ubuntu-22.04`;
  - instala `clang cmake ninja-build pkg-config libgtk-3-dev libfuse2`;
  - usa `subosito/flutter-action@v2` com `flutter-version: 3.47.5`;
  - roda `flutter test` e `packaging/appimage/build_appimage.sh ${GITHUB_REF_NAME#v}`;
  - faz `gh release create "$GITHUB_REF_NAME" dist/*.AppImage --generate-notes`, com `permissions: contents: write`.
- [ ] **Step 3:** `site/`: página estática em pt-BR que segue o design system (tokens.css, Roboto via Google Fonts, claro/escuro). Ela traz:
  - título e descrição do app;
  - o botão "Baixar a versão mais recente";
  - a lista de versões. O `app.js` busca `https://api.github.com/repos/uesleinasch/disk-cleanup/releases` e mostra nome, data e link do `.AppImage` de cada release. Se a API falhar, aparece o link "Ver versões no GitHub";
  - os requisitos (Ubuntu 22.04+, libfuse2).

  A página funciona em 360 px de largura. `pages.yml` usa `actions/upload-pages-artifact` (path `site`) e `actions/deploy-pages`, com `permissions: pages: write, id-token: write`.
- [ ] **Step 4:** Commit `ci: release do AppImage e página no GitHub Pages`.
- [ ] **Step 5:** Crie o repositório público e faça o push:
  - `gh repo create uesleinasch/disk-cleanup --public --source . --remote origin --description "Gerenciador de espaço em disco para Linux" --push`;
  - ative o Pages com origem em Actions: `gh api -X POST repos/uesleinasch/disk-cleanup/pages -f build_type=workflow`;
  - dispare `gh workflow run pages.yml` e espere com `gh run watch`.

  Esperado: `https://uesleinasch.github.io/disk-cleanup/` responde 200 (`curl -sI`).

### Task 26: Release v0.1.0

- [ ] **Step 1:** Confirme que `pubspec.yaml` tem `version: 0.1.0+1`, rode `flutter test` (tudo PASS) e confira que `git status` está limpo.
- [ ] **Step 2:** `git tag v0.1.0 && git push origin v0.1.0` e acompanhe com `gh run watch`. Esperado: o workflow de release termina com sucesso.
- [ ] **Step 3:** `gh release view v0.1.0` lista `disk-cleanup-0.1.0-x86_64.AppImage`. Baixe com `gh release download v0.1.0 -D /tmp/claude-…/scratchpad/rel`, rode `chmod +x` e execute. Esperado: o app abre. Peça ao usuário para confirmar visualmente.
- [ ] **Step 4:** Peça ao usuário para abrir `https://uesleinasch.github.io/disk-cleanup/` e conferir que a v0.1.0 aparece com o link de download.
