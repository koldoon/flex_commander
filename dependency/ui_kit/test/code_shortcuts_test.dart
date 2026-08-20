import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

/// Сочетания клавиш показа текста: что отпущено экрану и что добавлено.
///
/// Здесь проверяется решение — какие клавиши чьи. То, что отпущенное
/// действительно доходит до команд, проверяется на живом приложении
/// (`editor_keys_test.dart`).
void main() {
  const shortcuts = FcCodeShortcuts();

  test('Esc отпущен экрану: им закрывают редактор', () {
    expect(shortcuts.released, contains(CodeShortcutType.esc));
    expect(shortcuts.build(CodeShortcutType.esc), isEmpty);
  });

  test('просмотрщик отпускает и копирование: у него на Cmd-C своя команда', () {
    const viewer = FcCodeShortcuts(released: {CodeShortcutType.esc, CodeShortcutType.copy});

    expect(viewer.build(CodeShortcutType.copy), isEmpty);
    // А редактору копирование остаётся: своей команды на него у него нет.
    expect(shortcuts.build(CodeShortcutType.copy), isNotEmpty);
  });

  group('страница вверх и вниз', () {
    // В библиотеке они описаны — есть и намерение, и действие, — но не
    // назначены ни на одну клавишу. Живая проверка это и показала: PgUp и PgDn
    // в редакторе и просмотрщике не делали ничего.
    test('в библиотеке клавиш для них нет', () {
      const defaults = DefaultCodeShortcutsActivatorsBuilder();

      expect(defaults.build(CodeShortcutType.cursorMovePageUp) ?? const [], isEmpty);
      expect(defaults.build(CodeShortcutType.cursorMovePageDown) ?? const [], isEmpty);
    });

    test('мы их назначаем', () {
      expect(
        shortcuts.build(CodeShortcutType.cursorMovePageUp),
        contains(const SingleActivator(LogicalKeyboardKey.pageUp)),
      );
      expect(
        shortcuts.build(CodeShortcutType.cursorMovePageDown),
        contains(const SingleActivator(LogicalKeyboardKey.pageDown)),
      );
    });
  });

  test('всё остальное остаётся полю ровно таким, каким было', () {
    // Печатать, ходить курсором, отменять и копировать — его дело. Сравнение
    // с умолчанием, а не «непусто»: так видно, что мы **ничего** больше не
    // трогали, включая то, чего в умолчании и нет.
    const defaults = DefaultCodeShortcutsActivatorsBuilder();

    for (final type in CodeShortcutType.values) {
      if (shortcuts.released.contains(type) || FcCodeShortcuts.added.containsKey(type)) {
        continue;
      }
      expect(shortcuts.build(type), defaults.build(type), reason: '$type');
    }
  });
}
