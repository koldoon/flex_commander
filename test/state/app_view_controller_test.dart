import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Содержимое-подставка: считает, сколько раз его закрыли.
class _Content extends ChangeNotifier implements ViewportState {
  _Content(this.name);

  final String name;
  int closed = 0;

  @override
  bool get takesKeyboard => true;

  @override
  void close() => closed++;

  void poke() => notifyListeners();
}

/// Наложение того же вида, но другой экземпляр.
class _Other extends _Content {
  _Other(super.name);
}

/// У каждой области стопка состояний.
///
/// Внизу — то, что в области стоит; сверху — наложения. Замена меняет дно и
/// прежнее закрывает; наложение кладётся поверх, и под ним всё живо.
void main() {
  late AppRuntime runtime;
  const fullscreen = ViewportPosition.fullscreen;
  const left = ViewportPosition.left;

  setUp(() async {
    runtime = await testApp(
      provider: InMemoryTreeProvider([FakeEntry.directory('/home'), FakeEntry.file('/home/notes.txt', size: 3)]),
    );
  });

  test('панели стоят в своих областях с самого начала', () {
    expect(runtime.app.view.panelAt(left), same(runtime.app.left));
    expect(runtime.app.view.panelAt(ViewportPosition.right), same(runtime.app.right));
    expect(runtime.app.view.contentAt(fullscreen), isNull);
  });

  test('наложение скрывает панель целиком', () {
    // Копировать в то, чего не видно, нельзя: `F5` становится невыполнимой
    // сама собой, без отдельной проверки.
    runtime.app.view.pushViewportContent(left, _Content('quick-view'));

    expect(runtime.app.view.panelAt(left), isNull);
    expect(runtime.app.view.contentAt(left), isA<_Content>());
  });

  test('сняли наложение — под ним та же панель', () {
    final panel = runtime.app.left;
    runtime.app.view.pushViewportContent(left, _Content('quick-view'));
    runtime.app.view.popViewportContent(left);

    expect(runtime.app.view.panelAt(left), same(panel));
  });

  test('панель убрать нельзя — только заменить', () {
    runtime.app.view.popViewportContent(left);

    expect(runtime.app.view.panelAt(left), same(runtime.app.left));
  });

  test('замена закрывает прежнее, наложение — нет', () {
    final replaced = _Content('tree');
    runtime.app.view.setViewportContent(left, replaced);
    expect(replaced.closed, 0);

    final overlay = _Content('search');
    runtime.app.view.pushViewportContent(left, overlay);
    // Прежнее живо: под наложением остаются каталог, курсор и аренда.
    expect(replaced.closed, 0);

    runtime.app.view.popViewportContent(left);
    expect(overlay.closed, 1);
  });

  test('наложения уходят вместе с прежним дном', () {
    final overlay = _Content('search');
    runtime.app.view.pushViewportContent(left, overlay);
    runtime.app.view.setViewportContent(left, _Content('tree'));

    expect(overlay.closed, 1);
  });

  test('тот же вид поверх себя — замена слоя, а не второй слой', () {
    // Два просмотрщика друг над другом — не стопка, а недосмотр.
    final first = _Content('viewer');
    runtime.app.view.pushViewportContent(fullscreen, first);
    runtime.app.view.pushViewportContent(fullscreen, _Content('viewer again'));

    expect(runtime.app.view.stackAt(fullscreen), hasLength(1));
    expect(first.closed, 1);
  });

  test('в панельной области тот же вид — тоже замена слоя', () {
    // Правило одно на все области: раньше оно спрашивало, бывает ли область
    // пустой, и в панельной второе наложение ложилось вторым слоем.
    final first = _Content('quick view');
    runtime.app.view.pushViewportContent(left, first);
    runtime.app.view.pushViewportContent(left, _Content('quick view again'));

    expect(runtime.app.view.stackAt(left), hasLength(2), reason: 'панель на дне и одно наложение над ней');
    expect(first.closed, 1);
  });

  test('панель на дне наложением не заменяется', () {
    // Дно панельной области — сама панель, и её убирают не так. Тот же тип
    // сверху её перебить не должен, каким бы он ни был.
    final panel = runtime.app.view.stackAt(left).single;
    runtime.app.view.pushViewportContent(left, _Content('quick view'));

    expect(runtime.app.view.stackAt(left).first, same(panel));
    expect(runtime.app.view.panelAt(left), isNull, reason: 'наложение скрывает панель целиком');
  });

  test('другой вид ложится поверх, а не вместо', () {
    runtime.app.view.pushViewportContent(fullscreen, _Content('viewer'));
    runtime.app.view.pushViewportContent(fullscreen, _Other('editor'));

    expect(runtime.app.view.stackAt(fullscreen), hasLength(2));
  });

  test('область говорит и о том, что происходит внутри верхнего', () {
    // Иначе ряд функциональных кнопок замирает: он подписан на область, а
    // доступность его команд зависит от того, что внутри.
    final content = _Content('viewer');
    runtime.app.view.pushViewportContent(fullscreen, content);

    var notified = 0;
    runtime.app.view.addListener(() => notified++);
    content.poke();

    expect(notified, 1);
  });

  group('кому достаются клавиши', () {
    test('содержимое активной области — ему', () {
      final panel = runtime.app.view.stackAt(left).single;

      expect(runtime.app.view.takesKeys(panel), isTrue);
      expect(runtime.app.view.takesKeys(runtime.app.view.stackAt(ViewportPosition.right).single), isFalse);
    });

    test('наложение забирает клавиши у панели под собой', () {
      final panel = runtime.app.view.stackAt(left).single;
      final overlay = _Content('quick view');
      runtime.app.view.pushViewportContent(left, overlay);
      runtime.app.view.setFocus(left);

      // Панель под наложением жива и остаётся источником, но клавиши не её:
      // стрелки листают показ. Плашка по этому ответу и приглушается.
      expect(runtime.app.view.takesKeys(overlay), isTrue);
      expect(runtime.app.view.takesKeys(panel), isFalse);
    });

    test('командная строка клавиши панели оставляет', () {
      final panel = runtime.app.view.stackAt(left).single;
      final line = _Content('command line');
      runtime.app.view.setViewportContent(ViewportPosition.bottom, line);
      runtime.app.view.setFocus(ViewportPosition.bottom);

      // Утвердительно у обоих сразу, и это не ошибка: `F1`…`F12` и стрелки
      // достаются панели — курсор в ней ходит, пока набирают команду.
      expect(runtime.app.view.takesKeys(line), isTrue);
      expect(runtime.app.view.takesKeys(panel), isTrue);
    });

    test('где стоит содержимое, знает область, а не оно само', () {
      final overlay = _Content('quick view');
      runtime.app.view.pushViewportContent(left, overlay);

      expect(runtime.app.view.positionOf(overlay), left);
      expect(runtime.app.view.positionOf(_Content('нигде не стоит')), isNull);
    });
  });

  test('полноэкранное забирает ввод, а панель-источник остаётся известной', () {
    expect(runtime.app.view.activeArea, left);

    runtime.app.view.pushViewportContent(fullscreen, _Content('viewer'));

    expect(runtime.app.view.activeArea, fullscreen);
    expect(runtime.app.view.sourceArea, left, reason: 'источник файловой операции никуда не девается');
  });
}
