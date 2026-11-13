import 'dart:async';
import 'dart:io';

class ProcessRequest {
  const ProcessRequest({
    required this.executable,
    required this.environment,
    this.arguments = const [],
    this.workingDirectory,
  });

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String> environment;
}

class ManagedProcess {
  const ManagedProcess({
    required this.pid,
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    required this.cancel,
  });

  final int pid;
  final Stream<List<int>> stdout;
  final Stream<List<int>> stderr;
  final Future<int> exitCode;
  final Future<void> Function() cancel;
}

abstract interface class ProcessSupervisor {
  Future<ManagedProcess> start(ProcessRequest request);
}

abstract interface class CredentialStore {
  Future<void> write(String account, String secret);
  Future<String?> read(String account);
  Future<void> delete(String account);
}

class MemoryCredentialStore implements CredentialStore {
  final Map<String, String> _values = {};

  @override
  Future<void> write(String account, String secret) async {
    _values[account] = secret;
  }

  @override
  Future<String?> read(String account) async => _values[account];

  @override
  Future<void> delete(String account) async {
    _values.remove(account);
  }
}

class FileCredentialStore implements CredentialStore {
  FileCredentialStore(this.file);
  final File file;
  final Map<String, String> _values = {};
  var _loaded = false;

  void _load() {
    if (_loaded) return;
    _loaded = true;
    if (!file.existsSync()) return;
    for (final line in file.readAsLinesSync()) {
      final split = line.indexOf('\t');
      if (split <= 0) continue;
      _values[Uri.decodeComponent(line.substring(0, split))] =
          Uri.decodeComponent(line.substring(split + 1));
    }
  }

  void _persist() {
    file.parent.createSync(recursive: true);
    final lines = [
      for (final entry in _values.entries)
        '${Uri.encodeComponent(entry.key)}\t${Uri.encodeComponent(entry.value)}',
    ];
    file.writeAsStringSync('${lines.join('\n')}\n');
    if (!Platform.isWindows) {
      Process.runSync('chmod', ['600', file.path]);
    }
  }

  @override
  Future<void> write(String account, String secret) async {
    _load();
    _values[account] = secret;
    _persist();
  }

  @override
  Future<String?> read(String account) async {
    _load();
    return _values[account];
  }

  @override
  Future<void> delete(String account) async {
    _load();
    _values.remove(account);
    _persist();
  }
}

enum UpdateAvailability { unavailable }

class UpdateStatus {
  const UpdateStatus.unavailable()
    : availability = UpdateAvailability.unavailable;
  final UpdateAvailability availability;
}

abstract interface class AppUpdater {
  Future<UpdateStatus> check();
}

class DisabledUpdater implements AppUpdater {
  const DisabledUpdater();

  @override
  Future<UpdateStatus> check() async => const UpdateStatus.unavailable();
}

enum LicenseKind { localUnrestricted }

class LicenseStatus {
  const LicenseStatus.local() : kind = LicenseKind.localUnrestricted;
  final LicenseKind kind;
}

abstract interface class LicenseGate {
  LicenseStatus current();
}

class LocalLicense implements LicenseGate {
  const LocalLicense();

  @override
  LicenseStatus current() => const LicenseStatus.local();
}

class AdapterNotInstalled implements Exception {
  const AdapterNotInstalled();
  String get message =>
      'Nenhum adaptador de provedor está instalado nesta versão. Nenhuma chamada foi feita e nenhum consumo foi registrado.';
}

Never startProviderRun() {
  throw const AdapterNotInstalled();
}
