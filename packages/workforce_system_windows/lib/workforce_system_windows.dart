import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:workforce_core/workforce_core.dart';

const _genericCredential = 1;
const _persistLocalMachine = 2;

class WindowsCredentialStore implements CredentialStore {
  void _requireWindows() {
    if (!Platform.isWindows) {
      throw UnsupportedError(
        'O Credential Manager do AI Workforce só é usado no Windows.',
      );
    }
  }

  @override
  Future<void> write(String account, String secret) async {
    _requireWindows();
    final library = DynamicLibrary.open('advapi32.dll');
    final credWrite = library.lookupFunction<_CredWriteNative, _CredWrite>(
      'CredWriteW',
    );
    final target = 'AI Workforce/$account'.toNativeUtf16();
    final blob = secret.toNativeUtf16();
    final credential = calloc<Credential>();
    try {
      credential.ref
        ..type = _genericCredential
        ..targetName = target
        ..credentialBlobSize = secret.length * 2
        ..credentialBlob = blob.cast<Uint8>()
        ..persist = _persistLocalMachine
        ..userName = target;
      if (credWrite(credential, 0) == 0) {
        throw StateError('O Credential Manager recusou gravar a credencial.');
      }
    } finally {
      calloc.free(target);
      calloc.free(blob);
      calloc.free(credential);
    }
  }

  @override
  Future<String?> read(String account) async {
    _requireWindows();
    final library = DynamicLibrary.open('advapi32.dll');
    final credRead = library.lookupFunction<_CredReadNative, _CredRead>(
      'CredReadW',
    );
    final credFree = library.lookupFunction<_CredFreeNative, _CredFree>(
      'CredFree',
    );
    final target = 'AI Workforce/$account'.toNativeUtf16();
    final out = calloc<Pointer<Credential>>();
    try {
      if (credRead(target, _genericCredential, 0, out) == 0) return null;
      final credential = out.value.ref;
      final secret = credential.credentialBlob.cast<Utf16>().toDartString(
        length: credential.credentialBlobSize ~/ 2,
      );
      credFree(out.value.cast());
      return secret;
    } finally {
      calloc.free(target);
      calloc.free(out);
    }
  }

  @override
  Future<void> delete(String account) async {
    _requireWindows();
    final library = DynamicLibrary.open('advapi32.dll');
    final credDelete = library.lookupFunction<_CredDeleteNative, _CredDelete>(
      'CredDeleteW',
    );
    final target = 'AI Workforce/$account'.toNativeUtf16();
    try {
      credDelete(target, _genericCredential, 0);
    } finally {
      calloc.free(target);
    }
  }
}

final class Credential extends Struct {
  @Uint32()
  external int flags;
  @Uint32()
  external int type;
  external Pointer<Utf16> targetName;
  external Pointer<Utf16> comment;
  @Uint32()
  external int lastWrittenLow;
  @Uint32()
  external int lastWrittenHigh;
  @Uint32()
  external int credentialBlobSize;
  external Pointer<Uint8> credentialBlob;
  @Uint32()
  external int persist;
  @Uint32()
  external int attributeCount;
  external Pointer<Void> attributes;
  external Pointer<Utf16> targetAlias;
  external Pointer<Utf16> userName;
}

class WindowsJobSupervisor implements ProcessSupervisor {
  @override
  Future<ManagedProcess> start(ProcessRequest request) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('O Job Object só existe no Windows.');
    }
    final process = await Process.start(
      request.executable,
      request.arguments,
      workingDirectory: request.workingDirectory,
      environment: request.environment,
      mode: ProcessStartMode.normal,
    );
    final kernel = DynamicLibrary.open('kernel32.dll');
    final createJob = kernel.lookupFunction<_CreateJobNative, _CreateJob>(
      'CreateJobObjectW',
    );
    final assign = kernel.lookupFunction<_AssignNative, _Assign>(
      'AssignProcessToJobObject',
    );
    final terminate = kernel.lookupFunction<_TerminateNative, _Terminate>(
      'TerminateJobObject',
    );
    final job = createJob(nullptr, nullptr);
    final handle = _openProcess(kernel, process.pid);
    if (job != nullptr && handle != nullptr) assign(job, handle);
    // O cancelamento usa TerminateJobObject, que encerra os processos atribuídos ao job.
    return ManagedProcess(
      pid: process.pid,
      stdout: process.stdout,
      stderr: process.stderr,
      exitCode: process.exitCode,
      cancel: () async {
        if (job != nullptr) terminate(job, 1);
        process.kill(ProcessSignal.sigterm);
      },
    );
  }

  Pointer<Void> _openProcess(DynamicLibrary kernel, int pid) {
    final open = kernel.lookupFunction<_OpenProcessNative, _OpenProcess>(
      'OpenProcess',
    );
    return open(0x1F0FFF, 0, pid);
  }
}

typedef _CredWriteNative = Int32 Function(
  Pointer<Credential> credential,
  Uint32 flags,
);
typedef _CredWrite = int Function(Pointer<Credential> credential, int flags);
typedef _CredReadNative = Int32 Function(
  Pointer<Utf16> target,
  Uint32 type,
  Uint32 flags,
  Pointer<Pointer<Credential>> out,
);
typedef _CredRead = int Function(
  Pointer<Utf16> target,
  int type,
  int flags,
  Pointer<Pointer<Credential>> out,
);
typedef _CredDeleteNative = Int32 Function(
  Pointer<Utf16> target,
  Uint32 type,
  Uint32 flags,
);
typedef _CredDelete = int Function(Pointer<Utf16> target, int type, int flags);
typedef _CredFreeNative = Void Function(Pointer<Void> credential);
typedef _CredFree = void Function(Pointer<Void> credential);
typedef _CreateJobNative = Pointer<Void> Function(
  Pointer<Void> attributes,
  Pointer<Utf16> name,
);
typedef _CreateJob = Pointer<Void> Function(
  Pointer<Void> attributes,
  Pointer<Utf16> name,
);
typedef _AssignNative = Int32 Function(
  Pointer<Void> job,
  Pointer<Void> process,
);
typedef _Assign = int Function(Pointer<Void> job, Pointer<Void> process);
typedef _OpenProcessNative = Pointer<Void> Function(
  Uint32 access,
  Int32 inherit,
  Uint32 pid,
);
typedef _OpenProcess = Pointer<Void> Function(int access, int inherit, int pid);
typedef _TerminateNative = Int32 Function(Pointer<Void> job, Uint32 exitCode);
typedef _Terminate = int Function(Pointer<Void> job, int exitCode);

String describeCredentialStore() =>
    Platform.isWindows ? 'Credential Manager' : 'indisponível neste sistema';
