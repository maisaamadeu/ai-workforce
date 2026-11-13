import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:workforce_core/workforce_core.dart';
import 'package:workforce_system_macos/workforce_system_macos.dart';

void main() {
  test('o Keychain não é chamado fora do macOS', () {
    expect(
      MacOsKeychainStore().read('conta'),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test(
    'cancela a árvore do processo e não entrega segredo no ambiente',
    () async {
      final supervisor = PosixProcessSupervisor();
      final environment = sanitizeEnv({
        'PATH': Platform.environment['PATH'] ?? '/usr/bin',
        'ANTHROPIC_API_KEY': 'sk-secret',
      }, allowMetered: false);
      final managed = await supervisor.start(
        ProcessRequest(
          executable: 'bash',
          arguments: [
            '-c',
            'sleep 30 & if [ -n "\$ANTHROPIC_API_KEY" ]; then echo leaked; fi; echo started; wait',
          ],
          environment: environment,
        ),
      );
      final output = StringBuffer();
      final subscription = managed.stdout
          .transform(utf8.decoder)
          .listen(output.write);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await managed.cancel();
      await managed.exitCode.timeout(const Duration(seconds: 5));
      await subscription.cancel();
      expect(output.toString(), isNot(contains('leaked')));
      expect(output.toString(), contains('started'));
    },
  );
}
