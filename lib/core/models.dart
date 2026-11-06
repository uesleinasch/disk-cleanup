import '../cleanup/privileged_runner.dart';

enum RiskLevel { safe, attention, danger }

enum CleanupCategory { trash, cache, build, system, docker, largeFile }

enum DockerOp {
  inventory,
  pruneBuildCache,
  removeContainers,
  removeImages,
  removeVolumes,
}

sealed class CleanupAction {
  const CleanupAction();

  Map<String, Object?> toJson();

  static CleanupAction fromJson(Map<String, Object?> json) {
    List<String> strings(String key) =>
        (json[key] as List).cast<String>().toList();
    return switch (json['type']) {
      'delete' => DeletePathsAction(strings('paths')),
      'trash' => TrashPathsAction(strings('paths')),
      'emptyTrash' => const EmptyTrashAction(),
      'root' => RootAction([
        for (final c in json['commands'] as List)
          RootCommand.fromJson(Map<String, Object?>.from(c as Map)),
      ]),
      'docker' => DockerAction(
        DockerOp.values.byName(json['op'] as String),
        strings('ids'),
      ),
      final t => throw FormatException('Tipo de ação desconhecido: $t'),
    };
  }
}

class DeletePathsAction extends CleanupAction {
  const DeletePathsAction(this.paths);
  final List<String> paths;

  @override
  Map<String, Object?> toJson() => {'type': 'delete', 'paths': paths};
}

class TrashPathsAction extends CleanupAction {
  const TrashPathsAction(this.paths);
  final List<String> paths;

  @override
  Map<String, Object?> toJson() => {'type': 'trash', 'paths': paths};
}

class EmptyTrashAction extends CleanupAction {
  const EmptyTrashAction();

  @override
  Map<String, Object?> toJson() => {'type': 'emptyTrash'};
}

class RootAction extends CleanupAction {
  const RootAction(this.commands);
  final List<RootCommand> commands;

  @override
  Map<String, Object?> toJson() => {
    'type': 'root',
    'commands': [for (final c in commands) c.toJson()],
  };
}

class DockerAction extends CleanupAction {
  const DockerAction(this.op, this.ids);
  final DockerOp op;
  final List<String> ids;

  @override
  Map<String, Object?> toJson() => {
    'type': 'docker',
    'op': op.name,
    'ids': ids,
  };
}

class CleanupItem {
  const CleanupItem({
    required this.id,
    required this.category,
    required this.title,
    this.path,
    required this.note,
    required this.bytes,
    required this.risk,
    required this.requiresRoot,
    required this.preselected,
    this.lastModified,
    required this.action,
  });

  final String id;
  final CleanupCategory category;
  final String title;
  final String? path;
  final String note;
  final int bytes;
  final RiskLevel risk;
  final bool requiresRoot;
  final bool preselected;
  final DateTime? lastModified;
  final CleanupAction action;

  Map<String, Object?> toJson() => {
    'id': id,
    'category': category.name,
    'title': title,
    'path': path,
    'note': note,
    'bytes': bytes,
    'risk': risk.name,
    'requiresRoot': requiresRoot,
    'preselected': preselected,
    'lastModified': lastModified?.toIso8601String(),
    'action': action.toJson(),
  };

  factory CleanupItem.fromJson(Map<String, Object?> json) {
    final modified = json['lastModified'] as String?;
    return CleanupItem(
      id: json['id'] as String,
      category: CleanupCategory.values.byName(json['category'] as String),
      title: json['title'] as String,
      path: json['path'] as String?,
      note: json['note'] as String,
      bytes: json['bytes'] as int,
      risk: RiskLevel.values.byName(json['risk'] as String),
      requiresRoot: json['requiresRoot'] as bool,
      preselected: json['preselected'] as bool,
      lastModified: modified == null ? null : DateTime.parse(modified),
      action: CleanupAction.fromJson(
        Map<String, Object?>.from(json['action'] as Map),
      ),
    );
  }
}
