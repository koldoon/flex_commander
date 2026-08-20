import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:re_editor/re_editor.dart';

/// Сочетания клавиш текстового поля: что оно отпускает экрану и что мы ему
/// добавляем.
///
/// Открытый класс, а не частный: и то и другое — решения, а не подробности, и
/// проверяются они тестом.
///
/// `Esc` отпускают оба экрана: он закрывает их, и, утонув в виджете, оставил бы
/// человека внутри без выхода. Просмотрщик отпускает ещё и копирование — у него
/// на `Cmd-C` стоит своя команда, которая говорит, что случилось.
class FcTextShortcuts extends DefaultCodeShortcutsActivatorsBuilder {
  const FcTextShortcuts({this.released = const {CodeShortcutType.esc}});

  /// Клавиши, которые принадлежат экрану, а не тексту.
  final Set<CodeShortcutType> released;

  /// Чего в библиотеке не оказалось.
  ///
  /// Страница вверх и вниз у неё описаны — есть и намерение, и действие, — но
  /// не назначены ни на одну клавишу: ни в общей раскладке, ни в macOS-овской.
  /// Пока просмотрщик листался командами, `PgUp` и `PgDn` работали у нас
  /// самих; после переезда на общий показ их не подхватил никто.
  static const Map<CodeShortcutType, List<ShortcutActivator>> added = {
    CodeShortcutType.cursorMovePageUp: [SingleActivator(LogicalKeyboardKey.pageUp)],
    CodeShortcutType.cursorMovePageDown: [SingleActivator(LogicalKeyboardKey.pageDown)],
  };

  @override
  List<ShortcutActivator>? build(CodeShortcutType type) {
    if (released.contains(type)) {
      return const [];
    }

    final List<ShortcutActivator>? own = added[type];
    if (own == null) {
      return super.build(type);
    }

    // Добавляем, а не заменяем: своё к тому, что библиотека уже назначила.
    return [...?super.build(type), ...own];
  }
}
