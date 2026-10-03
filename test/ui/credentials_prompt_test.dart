import 'package:fc_api/fc_api.dart';
import 'package:flex_commander/ui/credentials_prompt.dart';
import 'package:flutter_test/flutter_test.dart';

/// Окно пароля на экранной стороне: вопросы ядра и свои — одной очередью
/// (`docs/spec/pdf-viewer.md`, §15.1).
void main() {
  const archive = CredentialRequest(realm: '7z:/a.7z', title: 'Encrypted archive', message: 'a.7z');
  const pdf = CredentialRequest(realm: 'pdf:/b.pdf', title: 'Password-protected PDF', message: 'b.pdf');

  late List<(String, String, String?)> sent;
  late CredentialsController controller;

  setUp(() {
    sent = [];
    controller = CredentialsController(
      onAnswer: (askId, realm, credential) => sent.add((askId, realm, credential?.password)),
    );
  });

  test('свой вопрос ждёт, пока ответят на вопрос ядра, — и наоборот', () async {
    controller.show('ask#1', archive);
    final answer = controller.obtain(pdf);

    expect(controller.pending, archive, reason: 'окно модальное: поверх не показывается');

    controller.answer(Credential.password('zip'));
    expect(sent.single, ('ask#1', '7z:/a.7z', 'zip'));
    expect(controller.pending, pdf);

    controller.answer(Credential.password('pdf'));
    expect((await answer)?.password, 'pdf');
    expect(sent, hasLength(1), reason: 'свой ответ за границу не уходит');
    expect(controller.pending, isNull);
  });

  test('здесь ничего не помнят: второй раз спрашивается снова', () async {
    final first = controller.obtain(pdf);
    controller.answer(Credential.password('pdf'));
    await first;

    final second = controller.obtain(pdf);
    expect(controller.pending, pdf);
    controller.answer(null);
    expect(await second, isNull);
  });

  test('закрытие снимает все вопросы отказом — никто не висит', () async {
    controller.show('ask#1', archive);
    final answer = controller.obtain(pdf);

    controller.dispose();

    expect(sent.single, ('ask#1', '7z:/a.7z', null));
    expect(await answer, isNull);
  });
}
