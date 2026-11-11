import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/process_runner.dart';

const kSecretCatalog = [
  '.ssh',
  '.gitconfig',
  '.gitignore_global',
  '.config/git',
  '.gnupg',
  '.local/share/keyrings',
];

const kSecretsTarExcludes = ['.gnupg/S.*', '.gnupg/*.lock', '.gnupg/.#lk*'];

String secretsFileName(DateTime date) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'secrets-${date.year}-${two(date.month)}-${two(date.day)}.tar.gz.gpg';
}

enum SecretsOutcome { ok, warnings, cancelled, failed }

class SecretsResult {
  const SecretsResult(
    this.outcome, {
    this.path,
    this.bytes = 0,
    this.message,
    this.warnings = const [],
  });

  final SecretsOutcome outcome;
  final String? path;
  final int bytes;
  final String? message;
  final List<String> warnings;
}

List<String> _lines(String text) => [
  for (final l in text.split('\n'))
    if (l.trim().isNotEmpty) l.trim(),
];

class SecretsArchiver {
  SecretsArchiver({required this.home, required this.runner, this.environment});

  final String home;
  final ProcessRunner runner;
  final Map<String, String>? environment;

  String? relativeToHome(String path) {
    final normalized = p.normalize(path);
    if (!p.isWithin(home, normalized)) return null;
    return p.relative(normalized, from: home);
  }

  Future<List<String>> detect() async {
    final items = <String>[
      for (final rel in kSecretCatalog)
        if (_exists(rel)) rel,
      ..._gitconfigIncludes(),
    ];
    for (final extra in await _gitReferenced()) {
      if (!items.any((i) => i == extra || p.isWithin(i, extra))) {
        items.add(extra);
      }
    }
    return items;
  }

  bool _exists(String rel) =>
      FileSystemEntity.typeSync(p.join(home, rel), followLinks: false) !=
      FileSystemEntityType.notFound;

  List<String> _gitconfigIncludes() {
    try {
      return [
        for (final e in Directory(home).listSync(followLinks: false))
          if (p.basename(e.path).startsWith('.gitconfig-')) p.basename(e.path),
      ]..sort();
    } on FileSystemException {
      return [];
    }
  }

  Future<List<String>> _gitReferenced() async {
    final r = await runner.run('git', const [
      'config',
      '--global',
      '--get-regexp',
      r'^(includeif\..*\.path|core\.excludesfile)$',
    ]);
    if (r.exitCode != 0) return [];
    final found = <String>[];
    for (final line in _lines(r.stdoutText)) {
      final space = line.indexOf(' ');
      if (space < 0) continue;
      var value = line.substring(space + 1).trim();
      if (value.startsWith('~/')) value = p.join(home, value.substring(2));
      if (!p.isAbsolute(value)) value = p.join(home, value);
      final rel = relativeToHome(value);
      if (rel != null && _exists(rel) && !found.contains(rel)) found.add(rel);
    }
    return found;
  }

  Future<SecretsResult> archive({
    required List<String> items,
    required String destination,
    required DateTime date,
    CancelToken? cancel,
  }) async {
    final name = secretsFileName(date);
    final partial = File(p.join(destination, '.$name.parcial'));
    final tar = Command('tar', [
      'czf',
      '-',
      '-C',
      home,
      for (final ex in kSecretsTarExcludes) '--exclude=$ex',
      '--',
      ...items,
    ]);
    final gpg = Command('gpg', [
      '--yes',
      '--pinentry-mode',
      'ask',
      '--symmetric',
      '--cipher-algo',
      'AES256',
      '--no-symkey-cache',
      '--output',
      partial.path,
    ]);

    final RunResult t, g;
    try {
      (t, g) = await runner.runPiped(
        tar,
        gpg,
        cancel: cancel,
        environment: environment,
      );
    } on ScanCancelled {
      await _remove(partial);
      rethrow;
    }

    final failure = _failure(t, g);
    if (failure != null) {
      await _remove(partial);
      return failure;
    }
    final out = await partial.rename(p.join(destination, name));
    final warnings = t.exitCode == 1 ? _lines(t.stderr) : const <String>[];
    return SecretsResult(
      warnings.isEmpty ? SecretsOutcome.ok : SecretsOutcome.warnings,
      path: out.path,
      bytes: await out.length(),
      warnings: warnings,
    );
  }

  Future<SecretsResult> extract({
    required String file,
    required String staging,
    CancelToken? cancel,
  }) async {
    final gpg = Command('gpg', [
      '--pinentry-mode',
      'ask',
      '--no-symkey-cache',
      '--status-fd',
      '2',
      '--decrypt',
      file,
    ]);
    final tar = Command('tar', ['xzf', '-', '-C', staging]);
    final (raw, t) = await runner.runPiped(
      gpg,
      tar,
      cancel: cancel,
      environment: environment,
    );
    final status = raw.stderr.toLowerCase();
    final g = RunResult(
      raw.exitCode,
      raw.stdout,
      [
        for (final l in _lines(raw.stderr))
          if (!l.startsWith('[GNUPG:]')) l,
      ].join('\n'),
    );
    if (g.exitCode != 0 && g.exitCode != 127) {
      if (status.contains('cancel') || status.contains('83886179')) {
        return const SecretsResult(
          SecretsOutcome.cancelled,
          message: 'A janela de senha foi fechada. Nada foi restaurado.',
        );
      }
      if (status.contains('bad_passphrase') ||
          status.contains('decryption_failed')) {
        return const SecretsResult(
          SecretsOutcome.failed,
          message: 'Senha errada. Os segredos não foram restaurados.',
        );
      }
    }
    if (g.exitCode == 0 && t.exitCode >= 2) {
      return SecretsResult(
        SecretsOutcome.failed,
        message:
            'O pacote de segredos está danificado: '
            '${_lines(t.stderr).lastOrNull ?? 'código ${t.exitCode}'}',
      );
    }
    return _failure(t, g) ?? SecretsResult(SecretsOutcome.ok, path: staging);
  }

  static SecretsResult? _failure(RunResult tar, RunResult gpg) {
    if (gpg.exitCode == 127) {
      return const SecretsResult(
        SecretsOutcome.failed,
        message: 'O gpg não está instalado. Instale o pacote gnupg.',
      );
    }
    if (tar.exitCode == 127) {
      return const SecretsResult(
        SecretsOutcome.failed,
        message: 'O tar não está instalado. Instale o pacote tar.',
      );
    }
    if (gpg.exitCode != 0) {
      final err = gpg.stderr.toLowerCase();
      if (err.contains('cancel')) {
        return const SecretsResult(
          SecretsOutcome.cancelled,
          message:
              'A janela de senha foi fechada. Os segredos não foram salvos.',
        );
      }
      if (err.contains('pinentry') || err.contains('inappropriate ioctl')) {
        return const SecretsResult(
          SecretsOutcome.failed,
          message:
              'Não foi possível abrir a janela de senha do sistema. '
              'Instale o pacote pinentry-gnome3.',
        );
      }
      return SecretsResult(
        SecretsOutcome.failed,
        message:
            'O gpg falhou: ${_lines(gpg.stderr).lastOrNull ?? 'código ${gpg.exitCode}'}',
      );
    }
    if (tar.exitCode >= 2) {
      return SecretsResult(
        SecretsOutcome.failed,
        message:
            'Não foi possível ler todos os itens: '
            '${_lines(tar.stderr).lastOrNull ?? 'código ${tar.exitCode}'}',
      );
    }
    return null;
  }

  static Future<void> _remove(File f) async {
    try {
      await f.delete();
    } on FileSystemException {
      return;
    }
  }
}
