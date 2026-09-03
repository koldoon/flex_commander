import 'package:fc_api/fc_api.dart';
import 'package:flex_commander/core/secrets_hub.dart';
import 'package:flutter_test/flutter_test.dart';

/// Секреты со стороны ядра: кто спрашивает, кто помнит и что бывает с ждущими.
///
/// Помнит ответы **эта** сторона: помнит тот, кто спрашивает. Иначе за
/// запомненным пришлось бы ходить через границу на каждое чтение записи из
/// архива (`docs/spec/client-server.md`, §7.3).
void main() {
  late SecretsHub secrets;
  late List<CredentialAsked> asked;

  CredentialRequest requestFor(String realm) =>
      CredentialRequest(realm: realm, title: 'Encrypted archive', message: 'sample.7z');

  setUp(() {
    asked = [];
    secrets = SecretsHub()..connect((event) => event is CredentialAsked ? asked.add(event) : null);
  });

  /// Ответить на последний заданный вопрос — так же, как это сделает экран.
  void answer(String? password) {
    final last = asked.last;
    secrets.answerCredential(
      last.askId,
      password == null ? null : Credential.password(password),
      realm: last.request.realm,
    );
  }

  test('спрошенное запоминается и второй раз не спрашивается', () async {
    final asking = secrets.obtain(requestFor('7z:/a.7z'));
    expect(asked, hasLength(1), reason: 'вопрос ушёл за границу');
    answer('тайна');

    expect((await asking)?.password, 'тайна');

    // Второй запрос по тому же адресу отвечает сам: 7z запускает программу на
    // каждое чтение записи, и окно иначе появлялось бы на каждый файл.
    expect((await secrets.obtain(requestFor('7z:/a.7z')))?.password, 'тайна');
    expect(asked, hasLength(1), reason: 'спрашивать было незачем');
  });

  test('другой адрес — свой вопрос', () async {
    final first = secrets.obtain(requestFor('7z:/a.7z'));
    answer('первый');
    await first;

    final second = secrets.obtain(requestFor('7z:/b.7z'));
    expect(asked.last.request.realm, '7z:/b.7z');
    answer('второй');

    expect((await second)?.password, 'второй');
  });

  test('забытое спрашивается заново', () async {
    final first = secrets.obtain(requestFor('7z:/a.7z'));
    answer('мимо');
    await first;

    secrets.forget('7z:/a.7z');
    expect(secrets.knows('7z:/a.7z'), isFalse);

    final second = secrets.obtain(requestFor('7z:/a.7z'));
    expect(asked, hasLength(2), reason: 'забытое — значит, надо спросить');
    answer('тайна');
    expect((await second)?.password, 'тайна');
  });

  test('отказ не запоминается', () async {
    final asking = secrets.obtain(requestFor('7z:/a.7z'));
    answer(null);

    expect(await asking, isNull);
    expect(secrets.knows('7z:/a.7z'), isFalse);
  });

  test('двое ждут одного ответа, а не двух вопросов', () async {
    // Обе панели открыли один архив: спрашивать дважды незачем.
    final first = secrets.obtain(requestFor('7z:/a.7z'));
    final second = secrets.obtain(requestFor('7z:/a.7z'));
    expect(asked, hasLength(1));
    answer('тайна');

    expect((await first)?.password, 'тайна');
    expect((await second)?.password, 'тайна');
  });

  test('спросить некому — отказ, а не ожидание', () async {
    // Экрана нет вовсе: линк ещё не подключён. Работа должна получить отказ, а
    // не встать навсегда.
    final alone = SecretsHub();

    expect(await alone.obtain(requestFor('7z:/a.7z')), isNull);
    expect(
      await alone.askElevation(const ElevationRequest(action: 'Write', path: '/etc/hosts', where: 'localhost')),
      isFalse,
    );
  });

  test('ядро уходит — ждущим отвечают отказом', () async {
    final asking = secrets.obtain(requestFor('7z:/a.7z'));
    secrets.dispose();

    expect(await asking, isNull);
  });
}
