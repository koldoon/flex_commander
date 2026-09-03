import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/bootstrap/bootstrap.dart';
import 'package:flutter_test/flutter_test.dart';

/// Приложение целиком — на **настоящем** изоляте.
///
/// Отдельным набором, а не общим прогоном, и это не осторожность: подставного
/// дерева и хранилища в памяти в тот изолят не отправить — они живут здесь. Там
/// поднимается настоящее ядро: настоящая файловая система, настоящий файл
/// настроек. Поэтому проверок здесь немного и все они про **границу**, а не про
/// поведение — поведение проверено на петле, и оно от двери не зависит
/// (`docs/spec/client-server.md`, §11, урок 14).
///
/// Домашний каталог у прогона настоящий, и трогать его нельзя: всё, что тут
/// делается, — чтение.
void main() {
  late AppRuntime runtime;

  setUp(() async {
    // Окно подставное: настоящее живёт в плагине, которого у прогона нет.
    // Всё остальное — настоящее, и ядро в том числе.
    runtime = await initIsolated(frontendModules(), overrides: AppOverrides(window: FakeWindowService()));
  });

  tearDown(() async {
    await runtime.dispose();
  });

  test('ядро поднялось и поздоровалось', () async {
    // Само по себе многое: в том изоляте собрались все ядровые модули,
    // прочитались настройки и завёлся корневой источник.
    expect(runtime.app.left, isNotNull);
    expect(runtime.app.left.source.scheme, 'fs', reason: 'корень — настоящая файловая система');
  });

  test('запуск открывает панели там, где их оставили', () async {
    await runtime.app.start();

    expect(runtime.app.left.path, isNotEmpty);
    expect(runtime.app.left.entries, isNotEmpty, reason: 'список приехал через порт');
  });

  test('курсор ходит: просьба туда, состояние обратно', () async {
    await runtime.app.start();
    final panel = runtime.app.left;

    panel.setCursorIndex(1);
    await waitUntil(() => panel.cursorIndex == 1);

    expect(panel.cursorIndex, 1);
  });

  test('содержимое каталога читается через порт', () async {
    await runtime.app.start();
    final panel = runtime.app.left;

    final names = await panel.namesIn(panel.path);

    expect(names, isNotEmpty, reason: 'имена приехали значениями');
  });

  test('ядро ушло — разговор кончается бедой, а не тишиной', () async {
    await runtime.app.start();
    await runtime.dispose();

    // Молчаливое ожидание ответа, которого больше некому дать, — худшее из
    // возможного: работа встала бы навсегда (`spec/client-server.md`, §11,
    // урок 2). `dispose` повторится в `tearDown`, и это не ошибка: закрывать
    // закрытое можно.
    await expectLater(runtime.app.left.namesIn('/'), throwsA(isA<Object>()));
  });
}
