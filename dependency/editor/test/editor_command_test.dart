import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_editor/frontend.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:fc_local_fs/backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Редактор как экран: открывается по F4, пишет обратно, спрашивает о
/// несохранённом.
///
/// На настоящем диске, а не на подставке: сохранение здесь — это временный
/// файл и переименование, и проверять их на подставке значило бы проверять
/// подставку.
void main() {
  late Directory temp;
  late AppRuntime runtime;
  late LocalTreeProvider provider;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('fc_editor');
    final root = await temp.resolveSymbolicLinks();
    await File(p.join(root, 'notes.txt')).writeAsString('раз\nдва\n');
    await File(p.join(root, 'windows.txt')).writeAsString('раз\r\nдва\r\n');
    await File(p.join(root, 'binary.bin')).writeAsBytes([0xC3, 0x28, 0xFF, 0x00]);

    provider = LocalTreeProvider(homePath: root, readInIsolate: false);
    runtime = await testApp(
      provider: provider,
      modules: featureModules(),
      settings: AppSettings(left: PanelSettings.defaults(root), right: PanelSettings.defaults(root)),
    );
    await runtime.app.start();
  });

  tearDown(() async {
    if (await temp.exists()) {
      // Права возвращаются перед уборкой: у каталога, с которого сняли `w`,
      // содержимое не удалить.
      await Process.run('chmod', ['-R', 'u+w', temp.path]);
      await temp.delete(recursive: true);
    }
  });

  Future<void> edit(String name) async {
    runtime.app.left.setCursorToName(name);
    await (runtime.commands.create(EditFileCommand.commandId)!).executeWith();
  }

  EditorScreen? openEditor() {
    final screen = runtime.app.view.contentAt(ViewportPosition.fullscreen);
    return screen is EditorScreen ? screen : null;
  }

  String fileText(String name) => File(p.join(temp.path, name)).readAsStringSync();

  /// Дождаться, пока случится ожидаемое.
  ///
  /// Запись идёт своим чередом, и окно уходит **до** неё: одного оборота
  /// очереди не хватает, а сколько именно их нужно — зависит от диска. Ждём
  /// самого исхода, а не заданного числа оборотов.
  /// Ответить на единственное открытое окно: согласиться или отказаться.
  ///
  /// Кнопки в чистом тесте не нажать, а `Enter` и `Esc` окна — это ровно
  /// `onSubmit` и `onDismiss` его описания.
  Future<void> answer({bool yes = true}) async {
    final dialog = runtime.app.view.dialogs.single;
    (yes ? dialog.onSubmit : dialog.onDismiss)!();
    await pumpEventQueue();
  }

  /// Сохранить и согласиться: запись теперь спрашивает.
  Future<void> save() async {
    await (runtime.commands.create(SaveFileCommand.commandId)!).executeWith();
    await answer();
    await waitUntil(() => openEditor()?.modified == false);
  }

  /// Сделать файл по-настоящему недоступным для записи.
  ///
  /// Права снимаются и с каталога: атомарная запись подменяет файл
  /// переименованием, а на это нужны права на каталог, а не на сам файл, —
  /// с одного файла снять их мало.
  ///
  /// false — снять не вышло: под `root` прав не отнять, ему можно всё, и
  /// проверять нечего.
  Future<bool> makeReadOnly(String name) async {
    await Process.run('chmod', ['a-w', p.join(temp.path, name)]);
    await Process.run('chmod', ['a-w', temp.path]);
    final node = runtime.app.left.session.nodeOf(runtime.app.left.entries.firstWhere((entry) => entry.name == name))!;
    return !await provider.canWriteTo(node);
  }

  group('открытие', () {
    test('F4 ставит редактор поверх панелей', () async {
      await edit('notes.txt');

      expect(openEditor(), isNotNull);
      expect(openEditor()!.controller.text, 'раз\nдва\n');
      expect(runtime.app.view.stackAt(ViewportPosition.fullscreen).map((state) => state.runtimeType), [EditorScreen]);
      // Панели никуда не делись — они под ним, в своих областях.
      expect(runtime.app.view.panelAt(ViewportPosition.left), isNotNull);
    });

    test('редактору нужен фокус — в отличие от просмотрщика', () async {
      await edit('notes.txt');

      expect(openEditor()!.takesKeyboard, isTrue);
    });

    test('не-текст на правку не открывается, и сказано почему', () async {
      await edit('binary.bin');

      expect(openEditor(), isNull);
      expect(runtime.app.toasts.current?.message, contains('UTF-8'));
    });
  });

  group('сохранение', () {
    test('пока не меняли — сохранять нечего', () async {
      await edit('notes.txt');

      expect(runtime.commands.isExecutable(runtime.commands.find(SaveFileCommand.commandId)!), isFalse);
    });

    test('правка уходит в файл', () async {
      await edit('notes.txt');
      openEditor()!.controller.text = 'раз\nдва\nтри\n';

      expect(openEditor()!.modified, isTrue);
      await save();

      expect(fileText('notes.txt'), 'раз\nдва\nтри\n');
      expect(openEditor()!.modified, isFalse);
    });

    test('переводы строк остаются такими, какими были', () async {
      // Иначе правка одной строки приходит в чужой diff как весь файл.
      await edit('windows.txt');
      openEditor()!.controller.text = 'раз\nдва\nтри\n';

      await save();

      expect(File(p.join(temp.path, 'windows.txt')).readAsBytesSync(), utf8.encode('раз\r\nдва\r\nтри\r\n'));
    });

    test('без подтверждения не пишет ничего', () async {
      // Единственное необратимое действие редактора: нажатая по ошибке `F2`
      // соседствует с `F3` и `F5`, а отмены записи нет.
      await edit('notes.txt');
      openEditor()!.controller.text = 'мимо';

      await (runtime.commands.create(SaveFileCommand.commandId)!).executeWith();
      expect(runtime.app.view.dialogs.single.title, 'Save changes');
      expect(fileText('notes.txt'), 'раз\nдва\n', reason: 'пока не ответили — не записано');

      await answer(yes: false);

      expect(fileText('notes.txt'), 'раз\nдва\n');
      expect(openEditor()!.modified, isTrue, reason: 'правки на месте, отказались только от записи');
    });

    test('в сообщении — полный путь, а не одно имя', () async {
      // Соглашаются на конкретный файл, и в системном каталоге это важнее
      // всего.
      await edit('notes.txt');
      openEditor()!.controller.text = 'иначе';

      await (runtime.commands.create(SaveFileCommand.commandId)!).executeWith();

      expect(openEditor()!.entry.path, contains('notes.txt'));
      await answer(yes: false);
    });

    test('Cmd-S спрашивает то же самое, что и F2', () async {
      // Одна команда — одна повадка: `Cmd-S` соседей по ряду не имеет, но
      // разное поведение у одной команды запрещено сквозным правилом.
      await edit('notes.txt');

      expect(runtime.commands.commandFor(KeyCombination.parse('Cmd-S'))?.id, SaveFileCommand.commandId);
      expect(runtime.commands.commandFor(KeyCombination.parse('F2'))?.id, SaveFileCommand.commandId);
    });

    test('не записалось — окно остаётся и говорит почему', () async {
      // Живой случай: `/etc/squid/squid.conf` по ssh. Раньше неудача записи
      // уходила в журнал, то есть мимо человека, а из колбэка окна — и вовсе
      // в отчёт о падении.
      await edit('notes.txt');
      openEditor()!.controller.text = 'некуда деть';
      if (!await makeReadOnly('notes.txt')) {
        return;
      }

      await (runtime.commands.create(SaveFileCommand.commandId)!).executeWith();
      await answer();
      await waitUntil(() => openEditor()?.modified == false || runtime.app.view.dialogs.isEmpty);

      expect(runtime.app.view.dialogs, isNotEmpty, reason: 'окно осталось — в нём ошибка');
      expect(openEditor(), isNotNull);
      expect(openEditor()!.modified, isTrue, reason: 'правки целы');
    });

    test('права файла переживают сохранение', () async {
      // Атомарная запись подменяет файл переименованием, и временный приносит
      // с собой права по умолчанию: без переноса `600` молча стало бы `644`.
      await Process.run('chmod', ['600', p.join(temp.path, 'notes.txt')]);
      final before = File(p.join(temp.path, 'notes.txt')).statSync().mode & 0x1FF;
      expect(before, 0x180, reason: 'иначе проверять нечего');

      await edit('notes.txt');
      openEditor()!.controller.text = 'правленое';
      await save();

      final after = File(p.join(temp.path, 'notes.txt')).statSync().mode & 0x1FF;
      expect(after, before, reason: 'заметить смену прав можно очень нескоро');
      expect(fileText('notes.txt'), 'правленое');
    });

    test('временный файл после себя не оставляется', () async {
      await edit('notes.txt');
      openEditor()!.controller.text = 'иначе';
      await save();

      final names = temp.listSync().map((entity) => p.basename(entity.path));
      expect(names.where((name) => name.contains('fc-save')), isEmpty);
    });
  });

  group('закрытие', () {
    test('без правок закрывается молча', () async {
      await edit('notes.txt');
      final close = runtime.commands.create(CloseEditorCommand.commandId)! as CloseEditorCommand;

      await close.executeWith();

      expect(runtime.app.view.contentAt(ViewportPosition.fullscreen), isNull);
    });

    test('с правками спрашивает, а не теряет молча', () async {
      await edit('notes.txt');
      openEditor()!.controller.text = 'несохранённое';

      // Спрашивать или нет, решает сама команда — снаружи «есть ли у неё
      // окно» больше никого не касается.
      expect(runtime.commands.run(CloseEditorCommand.commandId), isTrue);
      await pumpEventQueue();

      expect(runtime.app.view.dialogs.single.title, 'Unsaved changes');
      // Экран при этом ещё открыт: вопрос задан, ответа нет.
      expect(openEditor(), isNotNull);
    });

    test('Enter в окне выхода сохраняет, а не теряет', () async {
      // Раньше `Enter` стоял на `Discard`: самое частое «да, я закончил»
      // стирало работу.
      await edit('notes.txt');
      openEditor()!.controller.text = 'сохранить и выйти';

      await (runtime.commands.create(CloseEditorCommand.commandId)!).executeWith();
      await answer();
      await waitUntil(() => openEditor() == null);

      expect(fileText('notes.txt'), 'сохранить и выйти');
      expect(openEditor(), isNull, reason: 'записалось — можно и закрывать');
    });

    test('второго вопроса про запись при выходе нет', () async {
      // Согласие уже дано, вопрос был ровно про это.
      await edit('notes.txt');
      openEditor()!.controller.text = 'раз и всё';

      await (runtime.commands.create(CloseEditorCommand.commandId)!).executeWith();
      await answer();
      await waitUntil(() => openEditor() == null);

      expect(runtime.app.view.dialogs, isEmpty);
    });

    test('Esc в окне выхода оставляет экран открытым', () async {
      await edit('notes.txt');
      openEditor()!.controller.text = 'ещё поработаю';

      await (runtime.commands.create(CloseEditorCommand.commandId)!).executeWith();
      await answer(yes: false);

      expect(openEditor(), isNotNull);
      expect(fileText('notes.txt'), 'раз\nдва\n');
    });

    test('не записалось — экран остаётся открытым и с ошибкой', () async {
      await edit('notes.txt');
      openEditor()!.controller.text = 'некуда деть';
      if (!await makeReadOnly('notes.txt')) {
        return;
      }

      await (runtime.commands.create(CloseEditorCommand.commandId)!).executeWith();
      await answer();
      await waitUntil(() => runtime.app.view.dialogs.isEmpty);

      // Уйти, унеся правки, — ровно то, чего просили не делать.
      expect(openEditor(), isNotNull, reason: 'экран не закрылся');
      expect(openEditor()!.modified, isTrue, reason: 'правки целы');
      expect(runtime.app.view.dialogs, isNotEmpty, reason: 'окно осталось — в нём ошибка');
    });
  });

  group('права', () {
    test('файл без права записи открывается с вопросом', () async {
      if (!await makeReadOnly('notes.txt')) {
        return;
      }

      runtime.app.left.setCursorToName('notes.txt');
      unawaited((runtime.commands.create(EditFileCommand.commandId)!).executeWith());
      // Временем, а не оборотами очереди: право на запись выясняется попыткой
      // записать, то есть походом на диск, и сколько очередь ни крути, быстрее
      // диск не станет.
      await waitUntil(() => runtime.app.view.dialogs.isNotEmpty);

      expect(runtime.app.view.dialogs.single.title, 'Read-only file');
      // Пока не ответили, экрана нет: спрашивают до открытия, а не после часа
      // работы.
      expect(openEditor(), isNull);
    });

    test('открытый на чтение помечен, и сохранять в нём нечего', () async {
      if (!await makeReadOnly('notes.txt')) {
        return;
      }

      runtime.app.left.setCursorToName('notes.txt');
      unawaited((runtime.commands.create(EditFileCommand.commandId)!).executeWith());
      await pumpEventQueue();
      await answer();
      await waitUntil(() => openEditor() != null);

      expect(openEditor(), isNotNull);
      expect(openEditor()!.readOnly, isTrue);
      expect(
        runtime.commands.isExecutable(runtime.commands.find(SaveFileCommand.commandId)!),
        isFalse,
        reason: 'обещать запись, которой не будет, хуже отказа',
      );
    });

    test('повышение разрешено — в окне есть третий ответ', () async {
      // Служба берётся у приложения, и она должна быть **той самой**, что
      // раздаётся модулям: запасная выключена всегда, и с ней третьей кнопки
      // не появилось бы никогда.
      expect(runtime.app.elevation.enabled, isTrue, reason: 'по умолчанию повышение разрешено');

      if (!await makeReadOnly('notes.txt')) {
        return;
      }
      runtime.app.left.setCursorToName('notes.txt');
      unawaited((runtime.commands.create(EditFileCommand.commandId)!).executeWith());
      // Временем, а не оборотами очереди: право на запись выясняется попыткой
      // записать, то есть походом на диск, и сколько очередь ни крути, быстрее
      // диск не станет.
      await waitUntil(() => runtime.app.view.dialogs.isNotEmpty);

      expect(runtime.app.view.dialogs.single.title, 'Read-only file');
      await answer(yes: false);
    });

    test('согласились править всё равно — экран открыт и правится', () async {
      if (!await makeReadOnly('notes.txt')) {
        return;
      }
      runtime.app.left.setCursorToName('notes.txt');
      unawaited((runtime.commands.create(EditFileCommand.commandId)!).executeWith());
      await pumpEventQueue();

      // Третий ответ живёт в самом окне: `Enter` по-прежнему открывает на
      // чтение, и соглашаться вслепую на путь с паролем администратора не
      // приходится.
      final content = runtime.app.view.dialogs.single.content;
      expect(content, isA<CommandDialogConfirm>());
      final confirm = content as CommandDialogConfirm;
      expect(confirm.alternativeLabel, 'Edit anyway');

      confirm.onAlternative!();
      await waitUntil(() => openEditor() != null);

      expect(openEditor(), isNotNull);
      expect(openEditor()!.readOnly, isFalse, reason: 'правим как обычно — откажет сама запись');
    });

    test('отказ от вопроса не открывает ничего', () async {
      if (!await makeReadOnly('notes.txt')) {
        return;
      }

      runtime.app.left.setCursorToName('notes.txt');
      unawaited((runtime.commands.create(EditFileCommand.commandId)!).executeWith());
      await pumpEventQueue();
      await answer(yes: false);
      await pumpEventQueue();

      expect(openEditor(), isNull);
    });

    test('обычный файл открывается молча', () async {
      await edit('notes.txt');

      expect(runtime.app.view.dialogs, isEmpty);
      expect(openEditor()!.readOnly, isFalse);
    });

    test('canWriteTo отвечает попыткой, а не битами режима', () async {
      final node =
          runtime.app.left.session.nodeOf(runtime.app.left.entries.firstWhere((entry) => entry.name == 'notes.txt'))!;
      expect(await provider.canWriteTo(node), isTrue);

      if (!await makeReadOnly('notes.txt')) {
        return;
      }
      expect(await provider.canWriteTo(node), isFalse);

      // И файла эта проверка не трогает: ни содержимого, ни длины.
      expect(fileText('notes.txt'), 'раз\nдва\n');
    });
  });

  group('клавиши', () {
    test('в редакторе за F2 стоит сохранение, а не перенос строк', () async {
      await edit('notes.txt');

      expect(runtime.commands.commandFor(KeyCombination.parse('F2'))?.id, SaveFileCommand.commandId);
      expect(runtime.commands.commandFor(KeyCombination.parse('Esc'))?.id, CloseEditorCommand.commandId);
    });

    test('F9 прячет номера строк, не меняя подписи', () async {
      await edit('notes.txt');
      final numbers = runtime.commands.commandFor(KeyCombination.parse('F9'))!;

      // В редакторе номера включены: правя код, на строки ссылаются.
      expect(openEditor()!.showLineNumbers, isTrue);
      expect(numbers.label, 'Line Num');

      runtime.commands.dispatch(KeyCombination.parse('F9'));

      expect(openEditor()!.showLineNumbers, isFalse);
      // Подпись остаётся прежней: номера видно на самом экране.
      expect(runtime.commands.commandFor(KeyCombination.parse('F9'))!.label, 'Line Num');
      expect(runtime.app.toasts.current?.message, 'Show line numbers: Off');
    });

    test('номера строк помнятся между открытиями', () async {
      await edit('notes.txt');
      runtime.commands.dispatch(KeyCombination.parse('F9'));
      runtime.commands.dispatch(KeyCombination.parse('Esc'));

      await edit('notes.txt');

      expect(openEditor()!.showLineNumbers, isFalse);
    });

    test('поиск в редакторе — на тех же клавишах, что в просмотрщике', () async {
      await edit('notes.txt');

      expect(runtime.commands.commandFor(KeyCombination.parse('F7'))?.id, TextEditorFrontend.findCommandId);
      expect(runtime.commands.commandFor(KeyCombination.parse('Cmd-F'))?.id, TextEditorFrontend.findCommandId);
      expect(runtime.commands.commandFor(KeyCombination.parse('Shift-F7'))?.id, TextEditorFrontend.findNextCommandId);
      expect(runtime.commands.commandFor(KeyCombination.parse('Cmd-G'))?.id, TextEditorFrontend.findNextCommandId);
      expect(
        runtime.commands.commandFor(KeyCombination.parse('Shift-Cmd-G'))?.id,
        TextEditorFrontend.findPreviousCommandId,
      );
    });

    test('панельные клавиши в редакторе молчат', () async {
      await edit('notes.txt');

      expect(runtime.commands.commandFor(KeyCombination.parse('F5')), isNull);
      expect(runtime.commands.commandFor(KeyCombination.parse('F3')), isNull);
    });
  });
}
