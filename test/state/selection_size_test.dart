import 'package:flex_commander/model/settings/app_settings.dart';
import 'package:flex_commander/state/panel_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fake/in_memory_tree_provider.dart';

/// Размер помеченного: файлы известны сразу, каталоги считаются фоном.
void main() {
  late InMemoryTreeProvider provider;
  late PanelController panel;

  setUp(() async {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/docs'),
      FakeEntry.file('/home/docs/a.txt', size: 100),
      FakeEntry.directory('/home/docs/nested'),
      FakeEntry.file('/home/docs/nested/b.txt', size: 200),
      FakeEntry.directory('/home/bin'),
      FakeEntry.file('/home/bin/tool', size: 400),
      FakeEntry.file('/home/notes.txt', size: 50),
    ]);

    panel = PanelController(
      provider: provider,
      settings: PanelSettings.defaults('/home'),
      // Пауза перед подсчётом в тестах не нужна: она гасит частые нажатия.
      sizeScanDelay: Duration.zero,
    );
    await panel.openPath('/home');
  });

  tearDown(() => panel.dispose());

  /// Даёт фоновому подсчёту дойти до конца.
  Future<void> settle() async {
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  void mark(String name) {
    panel.setCursorToName(name);
    panel.toggleCurrentMark();
  }

  test('размер файла виден сразу', () async {
    mark('notes.txt');

    expect(panel.selectionSize, 50);
    expect(panel.selectionSizeIsFinal, isTrue);
  });

  test('каталог добавляет в сумму своё содержимое', () async {
    mark('docs');
    expect(panel.selectionSizeIsFinal, isFalse);

    await settle();

    expect(panel.selectionSize, 300);
    expect(panel.selectionSizeIsFinal, isTrue);
  });

  test('файлы и каталоги складываются', () async {
    mark('docs');
    mark('notes.txt');

    await settle();

    expect(panel.selectionSize, 350);
  });

  test('известное показывается сразу, каталоги досчитываются потом', () async {
    final seen = <int>[];
    panel.addListener(() => seen.add(panel.selectionSize));

    mark('notes.txt');
    mark('docs');

    // Обход ещё не начинался, но размер файла уже виден: ждать подсчёта
    // каталога, чтобы показать хоть что-то, незачем.
    expect(panel.selectionSize, 50);
    expect(panel.selectionSizeIsFinal, isFalse);

    await settle();

    expect(panel.selectionSize, 350);
    expect(seen.last, 350);
  });

  test('снятие пометки прекращает подсчёт', () async {
    mark('docs');
    panel.selection.clear();

    await settle();

    expect(panel.selectionSize, 0);
    expect(panel.selectionSizeIsFinal, isTrue);
  });

  test('новая пометка считается заново, а не поверх старой', () async {
    mark('docs');
    await settle();
    expect(panel.selectionSize, 300);

    panel.selection.clear();
    mark('bin');
    await settle();

    expect(panel.selectionSize, 400);
  });

  test('пока подсчёт идёт, сумма не выдаётся за окончательную', () async {
    mark('docs');

    // Обход ещё не закончился: показывать эту сумму как итог нельзя.
    expect(panel.selectionSizeIsFinal, isFalse);

    await settle();
    expect(panel.selectionSizeIsFinal, isTrue);
  });
}
