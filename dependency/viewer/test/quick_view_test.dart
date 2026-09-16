import 'dart:async';
import 'dart:convert';

import 'package:fc_core_api/fc_core_api.dart';

import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_text_viewer/fc_text_viewer.dart';
import 'package:fc_viewer/fc_viewer.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

/// Быстрый просмотр: соседняя панель показывает то, что под курсором.
///
/// Проверяется состояние, а не картинка: показ у него общий с полноэкранным
/// просмотрщиком, и проверен он там же.
void main() {
  late AppRuntime runtime;
  const left = ViewportPosition.left;
  const right = ViewportPosition.right;

  setUp(() async {
    runtime = await testApp(
      provider: InMemoryContentProvider([
        FakeEntry.directory('/home'),
        FakeEntry.file('/home/notes.txt', content: utf8.encode('раз\nдва\nтри')),
        FakeEntry.file('/home/other.txt', content: utf8.encode('другое')),
        FakeEntry.file('/home/big.log', size: 200 * 1024 * 1024),
        FakeEntry.directory('/home/docs'),
      ])..home = '/home',
      modules: featureModules(),
    );
    await runtime.app.start();
  });

  QuickViewHost? quickView([ViewportPosition position = right]) {
    final content = runtime.app.view.contentAt(position);
    return content is QuickViewHost ? content : null;
  }

  /// Что показано внутри хозяина: сам он ничего не показывает — он выбирает.
  TextViewerScreen? shown() {
    final host = quickView();
    final content = host == null ? null : innermost(host);
    return content is TextViewerScreen ? content : null;
  }

  /// Нажать `Shift-F3` — тем же путём, каким это делает клавиша.
  Future<void> toggle() async {
    expect(runtime.commands.dispatch(KeyCombination.parse('Shift-F3')), isTrue, reason: 'клавиша не привязана');
    await pumpEventQueue();
  }

  /// Подождать паузу перед чтением и само чтение.
  Future<void> settle() async {
    await Future<void>.delayed(QuickViewHost.defaultDelay * 2);
    await pumpEventQueue();
  }

  Future<void> cursorTo(String name) async {
    runtime.app.left.setCursorToName(name);
    await settle();
  }

  group('показанное не гаснет', () {
    test('пока читается следующий файл, на месте прежнего стоит он сам', () async {
      // Чтение придержано нарочно: иначе промежуточное состояние не поймать —
      // подставка отвечает быстрее, чем успевает пройти проверка.
      final held = _HeldProvider([
        FakeEntry.directory('/home'),
        FakeEntry.file('/home/notes.txt', content: utf8.encode('раз')),
        FakeEntry.file('/home/other.txt', content: utf8.encode('два')),
      ])..home = '/home';
      runtime = await testApp(provider: held, modules: featureModules());
      await runtime.app.start();

      runtime.app.left.setCursorToName('notes.txt');
      await toggle();
      held.release();
      await settle();
      final was = shown();
      expect(was, isNotNull, reason: 'первый файл показан');

      // Курсор ушёл дальше — чтение началось, но ещё не кончилось.
      held.hold();
      runtime.app.left.setCursorToName('other.txt');
      await settle();

      expect(shown(), same(was), reason: 'на месте прежнего стоит он сам, а не слово «Чтение…»');
      expect(quickView()!.notice, isNull, reason: 'слово на месте картинки — это и есть мигание');
      expect(quickView()!.loading, contains('other.txt'), reason: 'но сказать о чтении всё же надо');

      held.release();
      await settle();
      expect(shown(), isNot(same(was)), reason: 'дочитали — показали новое');
      expect(quickView()!.loading, isNull);
    });

    test('отказ гасит показанное: держать чужую картинку вместо отказа нельзя', () async {
      runtime.app.left.setCursorToName('notes.txt');
      await toggle();
      await settle();
      expect(shown(), isNotNull);

      await cursorTo('big.log');

      expect(shown(), isNull, reason: 'прежний файл не выдаётся за этот');
      expect(quickView()!.notice, contains('too large'));
      expect(quickView()!.loading, isNull);
    });
  });

  group('показ', () {
    test('Shift-F3 показывает содержимое в соседней области', () async {
      runtime.app.left.setCursorToName('notes.txt');

      await toggle();
      await settle();

      expect(quickView(), isNotNull);
      expect(shown()!.entry.name, 'notes.txt');
      expect(shown()!.controller.text, 'раз\nдва\nтри');
    });

    test('шаг курсора меняет показанное', () async {
      runtime.app.left.setCursorToName('notes.txt');
      await toggle();
      await settle();

      await cursorTo('other.txt');

      expect(shown()!.entry.name, 'other.txt');
      expect(shown()!.controller.text, 'другое');
    });

    test('быстрый перебор читает то, на чём остановились', () async {
      runtime.app.left.setCursorToName('notes.txt');
      await toggle();
      await settle();

      // Три шага подряд, быстрее паузы: читать каждый — значит открыть сотню
      // файлов на переборе стрелками.
      runtime.app.left.setCursorToName('docs');
      runtime.app.left.setCursorToName('other.txt');
      runtime.app.left.setCursorToName('notes.txt');
      await settle();

      expect(shown()!.entry.name, 'notes.txt');
      expect(shown()!.controller.text, 'раз\nдва\nтри');
    });

    test('Shift-F3 второй раз убирает просмотр', () async {
      await toggle();
      expect(quickView(), isNotNull);

      await toggle();

      expect(quickView(), isNull);
      expect(runtime.app.view.panelAt(right), isNotNull, reason: 'под наложением была панель');
    });
  });

  group('панель под наложением', () {
    test('цела: тот же каталог, курсор и пометка', () async {
      final panel = runtime.app.right;
      await panel.openPath('/home/docs');
      panel.setMarks({
        for (final entry in panel.entries)
          if (!entry.isParent) entry.name,
      });
      final directory = runtime.app.rightSession.directory;

      await toggle();
      await settle();

      expect(runtime.app.view.panelAt(right), isNull, reason: 'наложение скрывает панель целиком');
      expect(runtime.app.rightSession.directory, same(directory), reason: 'панель под наложением живёт');
    });

    test('копировать в неё нечего: панели там сейчас нет', () async {
      runtime.app.left.setCursorToName('notes.txt');

      await toggle();
      await settle();

      // Ни одной отдельной проверки ради этого не написано: `panelAt` отдаёт
      // null, и команда сама себя объявляет невыполнимой.
      expect(runtime.commands.isExecutable(runtime.commands.find('file.copy')!), isFalse);
    });
  });

  group('ввод', () {
    test('пока курсор в панели, ввод у неё', () async {
      await toggle();
      await settle();

      expect(runtime.app.view.activeArea, left);
    });

    test('Tab уводит ввод в просмотр, а не в спрятанную панель', () async {
      await toggle();
      await settle();

      runtime.app.toggleActivePanel();

      expect(runtime.app.view.activeArea, right);
      expect(runtime.app.left.active, isTrue, reason: 'источник файловой операции остался прежним');
      expect(runtime.app.view.sourceArea, left);
    });

    test('в просмотре работают клавиши просмотрщика', () async {
      runtime.app.left.setCursorToName('notes.txt');
      await toggle();
      await settle();
      runtime.app.toggleActivePanel();

      // Привязки объявлены `inState<ViewerScreen>`, а условие там `state is S`:
      // наследнику они достаются тем же объявлением.
      final wrapped = shown()!.wordWrap;
      expect(runtime.commands.dispatch(KeyCombination.parse('F2')), isTrue);

      expect(shown()!.wordWrap, !wrapped);
    });

    test('Tab из просмотра возвращает ввод файлам', () async {
      await toggle();
      await settle();
      runtime.app.toggleActivePanel();
      expect(runtime.app.view.activeArea, right);

      expect(runtime.commands.dispatch(KeyCombination.parse('Tab')), isTrue);

      expect(runtime.app.view.activeArea, left);
    });

    test('Esc из просмотра убирает его и возвращает ввод', () async {
      await toggle();
      await settle();
      runtime.app.toggleActivePanel();

      expect(runtime.commands.dispatch(KeyCombination.parse('Esc')), isTrue);
      await pumpEventQueue();

      expect(quickView(), isNull);
      expect(runtime.app.view.activeArea, left, reason: 'наложения нет — ввод там, где он и был');
    });
  });

  group('показывать нечего', () {
    test('каталог показывается, а не отговаривается словом', () async {
      runtime.app.left.setCursorToName('docs');

      await toggle();
      await settle();

      // Заглушка «Directory» была временной — до модуля сведений: теперь о
      // каталоге рассказывает он, и слов хозяину придумывать не приходится.
      expect(quickView()!.notice, isNull);
      expect(quickView()!.inner, isNotNull);
    });

    test('слишком большой файл говорит причину прямо в панели', () async {
      runtime.app.left.setCursorToName('big.log');

      await toggle();
      await settle();

      // Тостом нельзя: он выскакивал бы на каждом шаге курсора.
      expect(quickView()!.notice, contains('too large'));
    });

    test('вернулись на файл — снова текст, а не причина', () async {
      runtime.app.left.setCursorToName('big.log');
      await toggle();
      await settle();

      await cursorTo('notes.txt');

      expect(quickView()!.notice, isNull);
      expect(shown()!.controller.text, 'раз\nдва\nтри');
    });
  });
}

/// Подставка, у которой чтение можно придержать и отпустить.
///
/// Нужна ровно затем, чтобы поймать промежуточное состояние: в памяти файл
/// читается быстрее, чем успевает пройти проверка.
class _HeldProvider extends InMemoryContentProvider {
  _HeldProvider(super.entries);

  Completer<void>? _gate;

  void hold() => _gate = Completer<void>();

  void release() {
    final gate = _gate;
    _gate = null;
    if (gate != null && !gate.isCompleted) {
      gate.complete();
    }
  }

  @override
  Future<Stream<List<int>>> openRead(FsNode node, {int offset = 0}) async {
    final source = await super.openRead(node, offset: offset);
    final gate = _gate;
    if (gate == null) {
      return source;
    }
    return () async* {
      await gate.future;
      yield* source;
    }();
  }
}
