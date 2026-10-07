import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_text_kit/fc_text_kit.dart';
import 'package:fc_text_viewer/fc_text_viewer.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_viewer/fc_viewer.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

/// Старые кодировки в показе текста (`docs/spec/text-encodings.md`, §4).
void main() {
  const text = 'Мороз и солнце; день чудесный!\nЕщё ты дремлешь, друг прелестный.\n';

  late AppRuntime runtime;

  setUp(() async {
    runtime = await testApp(
      provider: InMemoryContentProvider([
        FakeEntry.directory('/home'),
        FakeEntry.file('/home/koi.txt', content: TextEncoding.koi8r.encode(text)),
        FakeEntry.file('/home/win.txt', content: TextEncoding.windows1251.encode(text)),
      ])..home = '/home',
      modules: featureModules(),
    );
    await runtime.app.start();
  });

  Future<TextViewerScreen> open(String name) async {
    runtime.app.left.setCursorToName(name);
    await runtime.commands.create(ViewFileCommand.commandId)!.executeWith();
    return runtime.app.view.contentAt(ViewportPosition.fullscreen)! as TextViewerScreen;
  }

  test('KOI8-R открывается по F3 по-русски, а не сведениями', () async {
    final screen = await open('koi.txt');
    expect(screen.encoding, TextEncoding.koi8r);
    expect(screen.controller.text, text);
  });

  test('F8 — окно кодировок; выбор перечитывает байты, Esc возвращает', () async {
    final screen = await open('koi.txt');

    expect(runtime.commands.dispatch(KeyCombination.parse('F8')), isTrue);
    await pumpEventQueue();
    final dialog = runtime.app.view.dialogs.single;
    expect(dialog.title, 'Encoding');

    screen.setEncoding(TextEncoding.windows1251);
    expect(screen.controller.text, isNot(text), reason: 'KOI8-R, прочтённый как Windows-1251, — каша');
    dialog.onDismiss!();
    expect(screen.encoding, TextEncoding.koi8r);
    expect(screen.controller.text, text);
  });

  test('в быстром просмотре выбранная кодировка помнится, пока он открыт', () async {
    const right = ViewportPosition.right;
    Future<TextViewerScreen> quick(String name) async {
      runtime.app.left.setCursorToName(name);
      await Future<void>.delayed(QuickViewHost.defaultDelay * 2);
      await pumpEventQueue();
      return innermost(runtime.app.view.contentAt(right)!) as TextViewerScreen;
    }

    runtime.app.left.setCursorToName('koi.txt');
    expect(runtime.commands.dispatch(KeyCombination.parse('Shift-F3')), isTrue);
    (await quick('koi.txt')).setEncoding(TextEncoding.cp866);

    expect((await quick('win.txt')).encoding, TextEncoding.windows1251, reason: 'у соседа своя');
    expect((await quick('koi.txt')).encoding, TextEncoding.cp866, reason: 'вернулись — как оставили');
  });
}
