import 'package:fc_ui_api/fc_ui_api.dart';
import 'dart:async';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/state/credentials_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Секреты: служба, её память и окно, которым спрашивают.
void main() {
  CredentialRequest requestFor(String realm) =>
      CredentialRequest(realm: realm, title: 'Encrypted archive', message: 'sample.7z');

  group('служба', () {
    test('спрошенное запоминается и второй раз не спрашивается', () async {
      final credentials = CredentialsController();
      addTearDown(credentials.dispose);

      final asking = credentials.obtain(requestFor('7z:/a.7z'));
      expect(credentials.pending, isNotNull);
      credentials.answer(Credential.password('тайна'));

      expect((await asking)?.password, 'тайна');
      expect(credentials.pending, isNull);

      // Второй запрос по тому же адресу отвечает сам: 7z запускает программу
      // на каждое чтение записи, и окно иначе появлялось бы на каждый файл.
      expect((await credentials.obtain(requestFor('7z:/a.7z')))?.password, 'тайна');
      expect(credentials.pending, isNull);
    });

    test('другой адрес — свой вопрос', () async {
      final credentials = CredentialsController();
      addTearDown(credentials.dispose);

      final first = credentials.obtain(requestFor('7z:/a.7z'));
      credentials.answer(Credential.password('первый'));
      await first;

      final second = credentials.obtain(requestFor('7z:/b.7z'));
      expect(credentials.pending?.realm, '7z:/b.7z');
      credentials.answer(Credential.password('второй'));

      expect((await second)?.password, 'второй');
    });

    test('забытое спрашивается заново', () async {
      final credentials = CredentialsController();
      addTearDown(credentials.dispose);

      final first = credentials.obtain(requestFor('7z:/a.7z'));
      credentials.answer(Credential.password('мимо'));
      await first;

      credentials.forget('7z:/a.7z');
      expect(credentials.knows('7z:/a.7z'), isFalse);

      final second = credentials.obtain(requestFor('7z:/a.7z'));
      expect(credentials.pending, isNotNull, reason: 'забытое — значит, надо спросить');
      credentials.answer(Credential.password('тайна'));
      expect((await second)?.password, 'тайна');
    });

    test('отказ не запоминается', () async {
      final credentials = CredentialsController();
      addTearDown(credentials.dispose);

      final asking = credentials.obtain(requestFor('7z:/a.7z'));
      credentials.answer(null);

      expect(await asking, isNull);
      expect(credentials.knows('7z:/a.7z'), isFalse);
    });

    test('двое ждут одного ответа, а не двух вопросов', () async {
      // Обе панели открыли один архив: спрашивать дважды незачем.
      final credentials = CredentialsController();
      addTearDown(credentials.dispose);

      final first = credentials.obtain(requestFor('7z:/a.7z'));
      final second = credentials.obtain(requestFor('7z:/a.7z'));
      credentials.answer(Credential.password('тайна'));

      expect((await first)?.password, 'тайна');
      expect((await second)?.password, 'тайна');
    });

    test('закрытие приложения отвечает отказом, а не оставляет ждать', () async {
      final credentials = CredentialsController();

      final asking = credentials.obtain(requestFor('7z:/a.7z'));
      credentials.dispose();

      expect(await asking, isNull);
    });
  });

  group('окно', () {
    Future<Credentials> pumpApp(WidgetTester tester) async {
      final provider = InMemoryTreeProvider([FakeEntry.directory('/home'), FakeEntry.file('/home/a.txt', size: 1)]);
      final runtime = await testApp(provider: provider, modules: featureModules());

      await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
      await runtime.app.start();
      await tester.pumpAndSettle();

      return runtime.app.credentials;
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
