import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/process_runner.dart';
import 'rsync_runner.dart';

class BrowserSpec {
  const BrowserSpec(this.id, this.label, this.paths);

  final String id;
  final String label;
  final List<String> paths;
}

const kBrowserCatalog = [
  BrowserSpec('brave', 'Brave', [
    '.config/BraveSoftware/Brave-Browser',
    '.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser',
  ]),
  BrowserSpec('chrome', 'Google Chrome', [
    '.config/google-chrome',
    '.var/app/com.google.Chrome/config/google-chrome',
  ]),
  BrowserSpec('chromium', 'Chromium', [
    '.config/chromium',
    'snap/chromium/common/chromium',
    '.var/app/org.chromium.Chromium/config/chromium',
  ]),
];

const kBrowserExcludedDirs = [
  'Cache',
  'Code Cache',
  'GPUCache',
  'CacheStorage',
  'ScriptCache',
  'GrShaderCache',
  'GraphiteDawnCache',
  'GPUPersistentCache',
  'DawnGraphiteCache',
  'DawnWebGPUCache',
  'ShaderCache',
  'component_crx_cache',
  'extensions_crx_cache',
  'Safe Browsing',
  'OptimizationGuidePredictionModels',
  'optimization_guide_model_store',
  'OnDeviceHeadSuggestModel',
  'screen_ai',
  'WasmTtsEngine',
  'Crash Reports',
  'Crashpad',
];

const kBrowserFolder = 'navegadores';

Future<void> writeBrowserFilter(File file) => file.writeAsString(
  [
    for (final dir in kBrowserExcludedDirs) '- $dir/',
    '- Singleton*',
    '- *.pma',
  ].join('\x00'),
);

class BrowserProfile {
  const BrowserProfile({required this.dir, required this.name, this.account});

  final String dir;
  final String name;
  final String? account;
}

class BrowserInstall {
  const BrowserInstall({
    required this.spec,
    required this.path,
    this.profiles = const [],
  });

  final BrowserSpec spec;
  final String path;
  final List<BrowserProfile> profiles;

  bool get isFlatpak => path.contains('/.var/app/');
}

List<BrowserProfile> parseLocalState(String json) {
  final root = jsonDecode(json);
  if (root is! Map) return [];
  final cache = (root['profile'] as Map?)?['info_cache'];
  if (cache is! Map) return [];
  final profiles = [
    for (final MapEntry(:key, :value) in cache.entries)
      if (key is String && value is Map)
        BrowserProfile(
          dir: key,
          name: value['name'] as String? ?? key,
          account: switch (value['user_name']) {
            final String s when s.isNotEmpty => s,
            _ => null,
          },
        ),
  ];
  profiles.sort((a, b) {
    if (a.dir == 'Default') return -1;
    if (b.dir == 'Default') return 1;
    return a.dir.compareTo(b.dir);
  });
  return profiles;
}

class BrowserProfiles {
  BrowserProfiles({
    required this.home,
    required this.rsync,
    String? hostname,
    bool Function(int pid)? pidAlive,
  }) : _hostname = hostname ?? Platform.localHostname,
       _pidAlive = pidAlive ?? ((pid) => Directory('/proc/$pid').existsSync());

  final String home;
  final RsyncRunner rsync;
  final String _hostname;
  final bool Function(int pid) _pidAlive;

  List<BrowserInstall> detect() => [
    for (final spec in kBrowserCatalog) ?_install(spec),
  ];

  BrowserInstall? _install(BrowserSpec spec) {
    for (final rel in spec.paths) {
      final path = p.join(home, rel);
      final state = File(p.join(path, 'Local State'));
      if (!state.existsSync()) continue;
      List<BrowserProfile> profiles;
      try {
        profiles = parseLocalState(state.readAsStringSync());
      } on FormatException {
        profiles = const [];
      } on FileSystemException {
        profiles = const [];
      }
      return BrowserInstall(spec: spec, path: path, profiles: profiles);
    }
    return null;
  }

  bool isOpen(BrowserInstall install) {
    final String target;
    try {
      target = Link(p.join(install.path, 'SingletonLock')).targetSync();
    } on FileSystemException {
      return false;
    }
    if (install.isFlatpak) return true;
    final dash = target.lastIndexOf('-');
    final pid = int.tryParse(target.substring(dash + 1));
    if (dash <= 0 || pid == null) return true;
    if (target.substring(0, dash) != _hostname) return false;
    return _pidAlive(pid);
  }

  Future<RsyncResult> copy(
    BrowserInstall install, {
    required String backupDir,
    required String filterFile,
    bool mirror = false,
    void Function(RsyncProgress)? onProgress,
    CancelToken? cancel,
  }) async {
    final dest = p.join(backupDir, kBrowserFolder, install.spec.id);
    await Directory(dest).create(recursive: true);
    return rsync.run(
      [
        '-aH',
        '--info=progress2',
        '--no-inc-recursive',
        '--stats',
        if (mirror) '--delete',
        '--from0',
        '--filter=. $filterFile',
        '${p.normalize(install.path)}/',
        '$dest/',
      ],
      onProgress: onProgress,
      cancel: cancel,
    );
  }
}
