import 'package:fc_api/fc_api.dart';
import 'package:flex_commander/state/screens_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Стопка экранов: снизу тот, с которого начинают, сверху — открытый поверх.
void main() {
  late ScreensController screens;
  late int notifications;

  setUp(() {
    screens = ScreensController();
    notifications = 0;
    screens.addListener(() => notifications++);
  });

  test('пока ничего не открыто, показывать нечего', () {
    expect(screens.active, isNull);
    expect(screens.stack, isEmpty);
  });

  test('открытый экран становится видимым', () {
    screens.open(const _Screen('files'));

    expect(screens.active?.id, 'files');
    expect(notifications, 1);
  });

  test('второй экран встаёт поверх, а закрывшись возвращает первый', () {
    screens.open(const _Screen('files'));
    screens.open(const _Screen('viewer'));

    expect(screens.active?.id, 'viewer');
    expect(screens.stack.map((screen) => screen.id), ['files', 'viewer']);

    screens.close('viewer');

    // Панели возвращаются такими же, какими были: заново их никто не открывал.
    expect(screens.active?.id, 'files');
  });

  test('тот же экран второй раз — замена, а не второй слой', () {
    screens.open(const _Screen('viewer'));
    screens.open(const _Screen('viewer'));

    expect(screens.stack, hasLength(1));
  });

  test('закрытие из середины стопки убирает именно его', () {
    screens.open(const _Screen('files'));
    screens.open(const _Screen('viewer'));

    screens.close('files');

    expect(screens.stack.map((screen) => screen.id), ['viewer']);
  });

  test('закрывать нечего — это не ошибка и не уведомление', () {
    screens.open(const _Screen('files'));
    final before = notifications;

    screens.close('viewer');

    expect(screens.active?.id, 'files');
    expect(notifications, before);
  });

  group('стопка говорит и о том, что внутри верхнего экрана', () {
    test('экран сообщил о себе — сообщила и стопка', () {
      // Ряд функциональных кнопок подписан на стопку, а доступность его команд
      // зависит от состояния экрана: есть ли в редакторе несохранённое.
      final screen = _LivingScreen('editor');
      screens.open(screen);
      final before = notifications;

      screen.change();

      expect(notifications, before + 1);
    });

    test('закрытый экран больше не слышен', () {
      final screen = _LivingScreen('editor');
      screens.open(screen);
      screens.close('editor');
      final before = notifications;

      screen.change();

      expect(notifications, before);
    });

    test('слушают верхний, а не тот, что под ним', () {
      final below = _LivingScreen('files');
      final above = _LivingScreen('editor');
      screens.open(below);
      screens.open(above);
      final before = notifications;

      below.change();

      expect(notifications, before, reason: 'нижний экран не виден — и говорить ему не о чем');

      above.change();

      expect(notifications, before + 1);
    });

    test('экран, который о себе не сообщает, стопке не мешает', () {
      screens.open(const _Screen('files'));

      expect(() => screens.close('files'), returnsNormally);
    });
  });
}

/// Экран, который сообщает о себе, — как настоящие: и редактор, и просмотрщик
/// умеют меняться, пока открыты.
class _LivingScreen extends ChangeNotifier implements Screen {
  _LivingScreen(this.id);

  @override
  final String id;

  @override
  bool get takesFocus => true;

  void change() => notifyListeners();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _Screen implements Screen {
  const _Screen(this.id);

  @override
  final String id;

  @override
  bool get takesFocus => false;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
