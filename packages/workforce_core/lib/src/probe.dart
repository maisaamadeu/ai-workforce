import 'dart:io';

import 'package:path/path.dart' as p;

import 'contracts.dart';

bool binaryOnPath(String name, String pathEnv, {String platform = 'linux'}) {
  final windows = platform == 'windows';
  final suffixes = windows ? const ['', '.exe', '.cmd'] : const [''];
  final separator = windows ? ';' : ':';
  final pathSeparator = windows ? '\\' : '/';
  for (final dir in pathEnv.split(separator)) {
    if (dir.isEmpty) continue;
    for (final suffix in suffixes) {
      final candidate = '$dir$pathSeparator$name$suffix';
      final file = File(candidate);
      if (!file.existsSync()) continue;
      if (windows) return true;
      final mode = file.statSync().mode;
      if (mode & 0x49 != 0) return true;
    }
  }
  return false;
}

Map<ProviderId, bool> probeInstalledClis([String? pathEnv]) {
  final path = pathEnv ?? Platform.environment['PATH'] ?? '';
  final platform = Platform.isWindows ? 'windows' : 'linux';
  return {
    for (final provider in ProviderId.values)
      provider: binaryOnPath(provider.binary, path, platform: platform),
  };
}

String dataDirectory() {
  final override = Platform.environment['AI_WORKFORCE_HOME'];
  if (override != null && override.isNotEmpty) return override;
  final home =
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      Directory.current.path;
  if (Platform.isMacOS)
    return p.join(home, 'Library', 'Application Support', 'AI Workforce');
  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'];
    return p.join(appData ?? home, 'AI Workforce');
  }
  final xdg = Platform.environment['XDG_DATA_HOME'];
  return p.join(xdg ?? p.join(home, '.local', 'share'), 'ai-workforce');
}

String dataFile() => p.join(dataDirectory(), 'workforce.sqlite');
