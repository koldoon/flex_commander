import 'package:fc_api/fc_api.dart';
import 'dart:async';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Секреты через границу: ядро спрашивает, экран показывает и отвечает.
///
/// Целиком, от вопроса до ответа: сам вопрос задаётся по ту сторону, где он в
/// жизни и возникает, — у того, кто работает с источником
/// (`docs/spec/client-server.md`, §7.3). Память и правила ожидания проверяются
/// отдельно, `test/core/secrets_test.dart`.
void main() {
  CredentialRequest requestFor(String realm) =>
      CredentialRequest(realm: realm, title: 'Encrypted archive', message: 'sample.7z');

  group('окно', () {
    /// Ядро, которое и спрашивает: секрет нужен тому, кто работает с
    /// источником.
    Future<Credentials> pumpApp(WidgetTester tester) async {
      final provider = InMemoryTreeProvider([FakeEntry.directory('/home'), FakeEntry.file('/home/a.txt', size: 1)]);
      final runtime = await testApp(provider: provider, modules: featureModules());

      await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
      await runtime.app.start();
      await tester.pumpAndSettle();

      return runtime.app.core!.secrets!;
    }

    testWidgets('вопрос показывается, а ввод скрыт', (tester) async {
      final credentials = await pumpApp(tester);

      unawaited(credentials.obtain(requestFor('7z:/sample.7z')));
      await tester.pumpAndSettle();

      expect(find.text('Encrypted archive'), findsOneWidget);
      expect(find.text('sample.7z'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);

      final field = tester.widget<TextField>(dialogField());
      expect(field.obscureText, isTrue, reason: 'пароль не показывают через плечо');
    });

    testWidgets('набранное уходит спрашивавшему', (tester) async {
      final credentials = await pumpApp(tester);

      final asking = credentials.obtain(requestFor('7z:/sample.7z'));
      await tester.pumpAndSettle();

      await tester.enterText(dialogField(), 'тайна');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      expect((await asking)?.password, 'тайна');
      expect(find.text('Encrypted archive'), findsNothing, reason: 'окно закрылось');
    });

    testWidgets('Esc отказывается отвечать', (tester) async {
      final credentials = await pumpApp(tester);

      final asking = credentials.obtain(requestFor('7z:/sample.7z'));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(await asking, isNull);
      expect(find.text('Encrypted archive'), findsNothing);
    });

    testWidgets('повторный вопрос говорит, что прошлый пароль не подошёл', (tester) async {
      final credentials = await pumpApp(tester);

      unawaited(credentials.obtain(requestFor('7z:/sample.7z').retrying()));
      await tester.pumpAndSettle();

      expect(find.text('Wrong password'), findsOneWidget);
    });
  });
}
