import 'dart:convert';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_editor/fc_editor.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

/// Правка файла на источнике по адресу.
///
/// Сохранение называет цель **путём** (`mem://alpha/srv/notes.txt`), и разбор
/// такого пути ядром — единственное, что отделяло редактор от сервера:
/// отказывал он на чужой схеме в начале, до самого источника дело не доходило
/// (`docs/spec/address-targets.md`).
///
/// На подставном источнике, объявленном по схеме `mem`: настоящий `ssh` стоит
/// на ней же, но сети в этом тесте не нужно.
void main() {
  late InMemoryAddressProvider server;

  Future<AppRuntime> app() async {
    final local = InMemoryTreeProvider([FakeEntry.directory('/home')])..home = '/home';
    return testApp(
      provider: local,
      modules: featureModules(),
      backend: [
        _AddressModule((address) {
          return server = InMemoryAddressProvider(
            address: address,
            entries: [FakeEntry.directory('/srv'), FakeEntry.file('/srv/notes.txt', content: utf8.encode('раз\n'))],
          );
        }),
      ],
      settings: AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home')),
    );
  }

  test('правка сохраняется на сервере, а не упирается в разбор пути', () async {
    final runtime = await app();
    await runtime.app.start();
    expect(await runtime.app.left.openPath('mem://alpha/srv'), isTrue);

    runtime.app.left.setCursorToName('notes.txt');
    await (runtime.commands.create(EditFileCommand.commandId)!).executeWith();
    await pumpEventQueue();

    final screen = runtime.app.view.contentAt(ViewportPosition.fullscreen);
    expect(screen, isA<EditorScreen>(), reason: 'редактор открывается панельной ссылкой — это работало и раньше');
    (screen! as EditorScreen).controller.text = 'раз\nдва\n';

    await (runtime.commands.create(SaveFileCommand.commandId)!).executeWith();
    // Запись подтверждают: окно спрашивает про конкретный файл.
    runtime.app.view.dialogs.single.onSubmit!();
    await pumpEventQueue();

    expect(runtime.app.view.dialogs, isEmpty, reason: 'окно осталось бы с ошибкой «Not supported»');
    expect(utf8.decode(server.entryAt('/srv/notes.txt')!.content), 'раз\nдва\n');
  });
}

/// Модуль, объявляющий источник по схеме `mem`.
class _AddressModule implements FcBackendModule {
  const _AddressModule(this.factory);

  final TreeProvider Function(Uri address) factory;

  @override
  String get id => 'test.addresses';

  @override
  String get title => 'Memory addresses';

  @override
  void installBackend(BackendRegistry registry) {
    registry.addressProvider('mem', () => TaskOperation<Uri, TreeProvider>((op, address) async => factory(address)));
  }
}
