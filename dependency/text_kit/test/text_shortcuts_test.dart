import 'package:fc_text_kit/fc_text_kit.dart';
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
  const shortcuts = FcTextShortcuts();

  test('Esc отпущен экрану: им закрывают редактор', () {
    expect(shortcuts.released, contains(CodeShortcutType.esc));
    expect(shortcuts.build(CodeShortcutType.esc), isEmpty);
  });

  test('просмотрщик отпускает и копирование: у него на Cmd-C своя команда', () {
    const viewer = FcTextShortcuts(released: {CodeShortcutType.esc, CodeShortcutType.copy});

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

  group('стрелки крутят текст там, где курсора не видно', () {
    const viewer = FcTextShortcuts(scrollsByArrows: true);

    test('в библиотеке клавиш для прокрутки нет и быть не должно', () {
      // Общей клавиши у неё не бывает: Ctrl-стрелки в VS Code, Cmd-стрелки в
      // других, а на macOS Ctrl-стрелка занята Mission Control. Умолчание тут
      // отнимало бы чужое сочетание — назначает приложение.
      const defaults = DefaultCodeShortcutsActivatorsBuilder();

      expect(defaults.build(CodeShortcutType.scrollLineUp) ?? const [], isEmpty);
      expect(defaults.build(CodeShortcutType.scrollLineDown) ?? const [], isEmpty);
    });

    test('в просмотрщике стрелка вызывает прокрутку', () {
      expect(viewer.build(CodeShortcutType.scrollLineUp), [const SingleActivator(LogicalKeyboardKey.arrowUp)]);
      expect(viewer.build(CodeShortcutType.scrollLineDown), [const SingleActivator(LogicalKeyboardKey.arrowDown)]);
    });

    test('и ход курсора отпускается, а не перекрывается', () {
      // Назначить стрелку двум типам сразу — значит положиться на порядок
      // значений в enum библиотеки: кто позже, тот и перезапишет.
      expect(viewer.build(CodeShortcutType.cursorMoveUp), isEmpty);
      expect(viewer.build(CodeShortcutType.cursorMoveDown), isEmpty);
    });

    test('в редакторе всё наоборот: стрелка ходит курсором', () {
      expect(shortcuts.build(CodeShortcutType.cursorMoveUp), isNotEmpty);
      expect(shortcuts.build(CodeShortcutType.cursorMoveDown), isNotEmpty);
      expect(shortcuts.build(CodeShortcutType.scrollLineUp) ?? const [], isEmpty);
      expect(shortcuts.build(CodeShortcutType.scrollLineDown) ?? const [], isEmpty);
    });

    test('выделение стрелками остаётся: у него своё намерение', () {
      // Shift-стрелки — другой тип, и Cmd-C в просмотрщике живёт вместе с ним.
      const defaults = DefaultCodeShortcutsActivatorsBuilder();

      expect(viewer.build(CodeShortcutType.selectionExtendUp), defaults.build(CodeShortcutType.selectionExtendUp));
      expect(viewer.build(CodeShortcutType.selectionExtendDown), defaults.build(CodeShortcutType.selectionExtendDown));
    });

    test('кроме двух стрелок просмотрщик не задевает ничего', () {
      const defaults = DefaultCodeShortcutsActivatorsBuilder();

      for (final type in CodeShortcutType.values) {
        if (viewer.released.contains(type) ||
            FcTextShortcuts.find.contains(type) ||
            FcTextShortcuts.added.containsKey(type) ||
            type == CodeShortcutType.cursorMoveUp ||
            type == CodeShortcutType.cursorMoveDown ||
            type == CodeShortcutType.scrollLineUp ||
            type == CodeShortcutType.scrollLineDown) {
          continue;
        }
        expect(viewer.build(type), defaults.build(type), reason: '$type');
      }
    });
  });

  test('встроенный поиск отпущен: панели у нас нет, Cmd-F за командой', () {
    for (final CodeShortcutType type in FcTextShortcuts.find) {
      expect(shortcuts.build(type), isEmpty, reason: '$type');
    }
  });

  test('всё остальное остаётся полю ровно таким, каким было', () {
    // Печатать, ходить курсором, отменять и копировать — его дело. Сравнение
    // с умолчанием, а не «непусто»: так видно, что мы **ничего** больше не
    // трогали, включая то, чего в умолчании и нет.
    const defaults = DefaultCodeShortcutsActivatorsBuilder();

    for (final type in CodeShortcutType.values) {
      if (shortcuts.released.contains(type) ||
          FcTextShortcuts.find.contains(type) ||
          FcTextShortcuts.added.containsKey(type)) {
        continue;
      }
      expect(shortcuts.build(type), defaults.build(type), reason: '$type');
    }
  });
}
