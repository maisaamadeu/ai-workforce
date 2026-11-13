import 'dart:io';

import 'package:test/test.dart';
import 'package:workforce_core/workforce_core.dart';
import 'package:workforce_system_windows/workforce_system_windows.dart';

void main() {
  test('o Credential Manager e o Job Object ficam no Windows', () {
    expect(
      WindowsCredentialStore().read('conta'),
      throwsA(isA<UnsupportedError>()),
    );
    expect(
      WindowsJobSupervisor().start(
        ProcessRequest(executable: 'cmd', environment: const {}),
      ),
      throwsA(isA<UnsupportedError>()),
    );
    expect(Platform.isWindows, isFalse);
  });
}
