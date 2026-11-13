import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:workforce_core/workforce_core.dart';

DynamicLibrary openPosixLibrary() {
  if (Platform.isMacOS)
    return DynamicLibrary.open('/usr/lib/libSystem.B.dylib');
  if (Platform.isLinux) return DynamicLibrary.open('libc.so.6');
  throw UnsupportedError(
    'O supervisor POSIX existe no macOS e no host de desenvolvimento Linux.',
  );
}

class PosixProcessSupervisor implements ProcessSupervisor {
  PosixProcessSupervisor() {
    final library = openPosixLibrary();
    _setpgid = library.lookupFunction<_SetpgidNative, _Setpgid>('setpgid');
    _kill = library.lookupFunction<_KillNative, _Kill>('kill');
  }

  static const _sigint = 2;
  static const _sigterm = 15;
  static const _sigkill = 9;

  late final _Setpgid _setpgid;
  late final _Kill _kill;

  @override
  Future<ManagedProcess> start(ProcessRequest request) async {
    final process = await Process.start(
      request.executable,
      request.arguments,
      workingDirectory: request.workingDirectory,
      environment: request.environment,
      mode: ProcessStartMode.normal,
    );
    _setpgid(process.pid, process.pid);
    return ManagedProcess(
      pid: process.pid,
      stdout: process.stdout,
      stderr: process.stderr,
      exitCode: process.exitCode,
      cancel: () => _cancel(process),
    );
  }

  Future<void> _cancel(Process process) async {
    void signal(int value) {
      if (_kill(-process.pid, value) != 0) _kill(process.pid, value);
    }

    signal(_sigint);
    if (await _exited(process, const Duration(milliseconds: 250))) return;
    signal(_sigterm);
    if (await _exited(process, const Duration(milliseconds: 350))) return;
    signal(_sigkill);
    process.kill(ProcessSignal.sigkill);
  }

  Future<bool> _exited(Process process, Duration budget) async {
    try {
      await process.exitCode.timeout(budget);
      return true;
    } on TimeoutException {
      return false;
    }
  }
}

typedef _SetpgidNative = Int32 Function(Int32 pid, Int32 pgid);
typedef _Setpgid = int Function(int pid, int pgid);
typedef _KillNative = Int32 Function(Int32 pid, Int32 sig);
typedef _Kill = int Function(int pid, int sig);

class MacOsKeychainStore implements CredentialStore {
  static const service = 'ai.workforce.credentials';

  void _requireMacOs() {
    if (!Platform.isMacOS) {
      throw UnsupportedError('O Keychain do AI Workforce só é usado no macOS.');
    }
  }

  @override
  Future<void> write(String account, String secret) async {
    _requireMacOs();
    final result = await Process.run('security', [
      'add-generic-password',
      '-U',
      '-s',
      service,
      '-a',
      account,
      '-w',
      secret,
    ]);
    if (result.exitCode != 0) {
      throw StateError('O Keychain recusou gravar a credencial.');
    }
  }

  @override
  Future<String?> read(String account) async {
    _requireMacOs();
    final result = await Process.run('security', [
      'find-generic-password',
      '-s',
      service,
      '-a',
      account,
      '-w',
    ]);
    if (result.exitCode != 0) return null;
    final value = '${result.stdout}'.trimRight();
    return value.isEmpty ? null : value;
  }

  @override
  Future<void> delete(String account) async {
    _requireMacOs();
    await Process.run('security', [
      'delete-generic-password',
      '-s',
      service,
      '-a',
      account,
    ]);
  }
}

String describeCredentialStore() =>
    Platform.isMacOS ? 'Keychain' : 'indisponível neste sistema';
