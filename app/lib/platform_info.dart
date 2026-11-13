import 'dart:ffi';
import 'dart:io';

import 'package:workforce_system_macos/workforce_system_macos.dart';
import 'package:workforce_system_windows/workforce_system_windows.dart'
    as windows;

String supervisorLabel() {
  if (Platform.isWindows) return 'Job Object';
  if (Platform.isMacOS || Platform.isLinux) {
    try {
      PosixProcessSupervisor();
      return Platform.isMacOS
          ? 'Grupo de processos POSIX'
          : 'Grupo de processos POSIX no host Linux';
    } on Object {
      return 'Supervisor indisponível';
    }
  }
  return 'Supervisor indisponível';
}

String credentialLabel() {
  if (Platform.isMacOS) return describeCredentialStore();
  if (Platform.isWindows) return windows.describeCredentialStore();
  return 'Arquivo local do host de desenvolvimento';
}

String architectureLabel() => Abi.current().toString();
