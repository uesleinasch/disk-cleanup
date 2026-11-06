import '../core/models.dart';
import '../core/process_runner.dart';

String _quote(String value) {
  if (value.contains("'") || value.contains('\u0000') || value.contains('\n')) {
    throw ArgumentError.value(value, 'value', 'Caractere inválido');
  }
  return "'$value'";
}

String _validated(String value, RegExp pattern, String what) {
  if (!pattern.hasMatch(value)) {
    throw ArgumentError.value(value, what, 'Formato inválido');
  }
  return value;
}

final _snapName = RegExp(r'^[a-z0-9][a-z0-9-]*$');
final _snapRevision = RegExp(r'^[0-9]+$');
final _dockerId = RegExp(r'^[a-f0-9]{12,64}$');
final _dockerVolume = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]*$');

sealed class RootCommand {
  const RootCommand();

  String toShell();

  Map<String, Object?> toJson();

  static RootCommand fromJson(Map<String, Object?> json) {
    return switch (json['type']) {
      'journalVacuum' => JournalVacuum(),
      'aptClean' => AptClean(),
      'snapRemove' => SnapRemoveRevision(
        json['name'] as String,
        json['revision'] as String,
      ),
      'duMeasure' => DuMeasure(json['path'] as String),
      'docker' => DockerCli(
        DockerOp.values.byName(json['op'] as String),
        (json['ids'] as List).cast<String>().toList(),
      ),
      final t => throw FormatException('Tipo de comando root desconhecido: $t'),
    };
  }
}

final class JournalVacuum extends RootCommand {
  JournalVacuum();

  @override
  String toShell() => '/usr/bin/journalctl --vacuum-size=500M';

  @override
  Map<String, Object?> toJson() => {'type': 'journalVacuum'};
}

final class AptClean extends RootCommand {
  AptClean();

  @override
  String toShell() => '/usr/bin/apt-get clean';

  @override
  Map<String, Object?> toJson() => {'type': 'aptClean'};
}

final class SnapRemoveRevision extends RootCommand {
  SnapRemoveRevision(String name, String revision)
    : name = _validated(name, _snapName, 'name'),
      revision = _validated(revision, _snapRevision, 'revision');

  final String name;
  final String revision;

  @override
  String toShell() =>
      "/usr/bin/snap remove ${_quote(name)} --revision=${_quote(revision)}";

  @override
  Map<String, Object?> toJson() => {
    'type': 'snapRemove',
    'name': name,
    'revision': revision,
  };
}

final class DuMeasure extends RootCommand {
  DuMeasure(String path) : path = _validatedPath(path);

  final String path;

  static String _validatedPath(String path) {
    _quote(path);
    if (!path.startsWith('/') || path.split('/').contains('..')) {
      throw ArgumentError.value(path, 'path', 'Caminho inválido');
    }
    return path;
  }

  @override
  String toShell() => '/usr/bin/du -sx -B1 -0 ${_quote(path)}';

  @override
  Map<String, Object?> toJson() => {'type': 'duMeasure', 'path': path};
}

final class DockerCli extends RootCommand {
  DockerCli(this.op, List<String> ids) : ids = List.unmodifiable(ids) {
    switch (op) {
      case DockerOp.inventory:
      case DockerOp.pruneBuildCache:
        if (ids.isNotEmpty) {
          throw ArgumentError.value(ids, 'ids', 'Esta operação não aceita ids');
        }
      case DockerOp.removeContainers:
      case DockerOp.removeImages:
      case DockerOp.removeVolumes:
        if (ids.isEmpty) {
          throw ArgumentError.value(ids, 'ids', 'Informe ao menos um id');
        }
        final pattern = op == DockerOp.removeVolumes
            ? _dockerVolume
            : _dockerId;
        for (final id in ids) {
          _validated(id, pattern, 'ids');
        }
    }
  }

  final DockerOp op;
  final List<String> ids;

  @override
  String toShell() {
    String quoted() => ids.map(_quote).join(' ');
    return switch (op) {
      DockerOp.inventory =>
        "/usr/bin/docker system df -v --format '{{json .}}'",
      DockerOp.pruneBuildCache => '/usr/bin/docker builder prune -f',
      DockerOp.removeContainers => '/usr/bin/docker rm ${quoted()}',
      DockerOp.removeImages => '/usr/bin/docker rmi ${quoted()}',
      DockerOp.removeVolumes => '/usr/bin/docker volume rm ${quoted()}',
    };
  }

  @override
  Map<String, Object?> toJson() => {
    'type': 'docker',
    'op': op.name,
    'ids': ids,
  };
}

String buildRootScript(List<RootCommand> cmds) => [
  for (var i = 0; i < cmds.length; i++)
    '${cmds[i].toShell()}; echo "__dc_status $i \$?"',
].join('\n');

class RootBatchResult {
  const RootBatchResult({
    required this.cancelled,
    required this.exitCodes,
    required this.stdout,
  });

  final bool cancelled;
  final Map<int, int> exitCodes;
  final String stdout;
}

class PrivilegedRunner {
  PrivilegedRunner(this._runner);

  final ProcessRunner _runner;
  static final _status = RegExp(r'^__dc_status (\d+) (\d+)$');

  Future<RootBatchResult> run(List<RootCommand> cmds) async {
    if (cmds.isEmpty) {
      return const RootBatchResult(cancelled: false, exitCodes: {}, stdout: '');
    }
    final result = await _runner.run('pkexec', [
      '/bin/sh',
      '-c',
      buildRootScript(cmds),
    ]);
    final text = result.stdoutText;
    final codes = <int, int>{};
    var next = 0;
    for (final line in text.split(RegExp('[\n\u0000]'))) {
      final m = _status.firstMatch(line.trimRight());
      if (m == null || next >= cmds.length) continue;
      final index = int.tryParse(m[1]!);
      final code = int.tryParse(m[2]!);
      if (index != next || code == null) continue;
      codes[index!] = code;
      next++;
    }
    final cancelled =
        (result.exitCode == 126 || result.exitCode == 127) && codes.isEmpty;
    return RootBatchResult(
      cancelled: cancelled,
      exitCodes: codes,
      stdout: text,
    );
  }
}
