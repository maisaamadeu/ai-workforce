import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:workforce_core/workforce_core.dart';

import 'package:ai_workforce/main.dart';

void main() {
  testWidgets('cria um workspace e troca o modo global', (tester) async {
    final workforce = LocalWorkforce.open(path: ':memory:');
    addTearDown(workforce.close);
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(AiWorkforceApp(workforce: workforce));
    await tester.pump();

    expect(find.text('AI Workforce'), findsOneWidget);
    expect(find.text('Econômico'), findsOneWidget);
    expect(find.text('Nenhum workspace ainda.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('workspace-name')), 'STI 3');
    await tester.ensureVisible(find.text('Criar'));
    await tester.tap(find.text('Criar'));
    await tester.pump();

    expect(find.text('STI 3'), findsOneWidget);
    expect(workforce.snapshot().workspaces.single.name, 'STI 3');

    await tester.ensureVisible(find.text('Equilibrado'));
    await tester.tap(find.text('Equilibrado'));
    await tester.pump();
    expect(workforce.snapshot().organization.mode, OperationMode.balanced);

    await tester.ensureVisible(find.text('STI 3'));
    await tester.tap(find.text('STI 3'));
    await tester.pump();
    expect(find.text('Políticas de consumo'), findsOneWidget);

    final directory = Directory.systemTemp.createTempSync('ai-workforce-ui');
    addTearDown(() => directory.deleteSync(recursive: true));
    await tester.ensureVisible(find.byKey(const Key('project-path')));
    await tester.enterText(
      find.byKey(const Key('project-path')),
      directory.path,
    );
    await tester.enterText(find.byType(TextField).first, 'Núcleo');
    await tester.ensureVisible(find.text('Registrar'));
    await tester.tap(find.text('Registrar'));
    await tester.pump();
    expect(find.text('Núcleo'), findsOneWidget);
    expect(find.text(directory.resolveSymbolicLinksSync()), findsOneWidget);
  });
}
