import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

/// Какие клавиши показ текста отпускает экрану.
///
/// Виджетом это не проверить: `re_editor` считает подсветку в изоляте, а
/// `flutter_test` живёт на поддельном времени — прогон с настоящим `CodeEditor`
/// не завершается. Поэтому проверяется решение (что отпущено), а то, что
/// отпущенное действительно доходит до команд, — живым запуском.
void main() {
  const shortcuts = FcCodeShortcuts();

  test('Esc отпущен экрану: им закрывают редактор', () {
    expect(shortcuts.released, contains(CodeShortcutType.esc));
    expect(shortcuts.build(CodeShortcutType.esc), isEmpty);
  });

  test('всё остальное остаётся редактору ровно таким, каким было', () {
    // Печатать, ходить курсором, отменять и копировать — его дело. Сравнение
    // с умолчанием, а не «непусто»: так видно, что мы **ничего** больше не
    // трогали, включая то, чего в умолчании и нет.
    const defaults = DefaultCodeShortcutsActivatorsBuilder();

    for (final type in CodeShortcutType.values) {
      if (shortcuts.released.contains(type)) {
        continue;
      }
      expect(shortcuts.build(type), defaults.build(type), reason: '$type');
    }
  });
}
