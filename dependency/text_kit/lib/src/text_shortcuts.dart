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
/// на `Cmd-C` стоит своя команда, которая говорит, что случилось, — и ход
/// курсора стрелками: там они крутят текст ([scrollsByArrows]).
class FcTextShortcuts extends DefaultCodeShortcutsActivatorsBuilder {
  const FcTextShortcuts({this.released = const {CodeShortcutType.esc}, this.scrollsByArrows = false});

  /// Сочетания встроенного поиска — отпускаются **всегда**, независимо от
  /// [released].
  ///
  /// `Cmd-F` принадлежит нашей команде, а панель, которую эти клавиши
  /// открывали, мы не рисуем: нажатие уходило бы в пустоту. Отдельным
  /// множеством, а не умолчанием [released], чтобы экран, назвавший свои
  /// клавиши, не отменил это ненароком.
  static const Set<CodeShortcutType> find = {
    CodeShortcutType.find,
    CodeShortcutType.findToggleMatchCase,
    CodeShortcutType.findToggleRegex,
  };

  /// Клавиши, которые принадлежат экрану, а не тексту.
  final Set<CodeShortcutType> released;

  /// Стрелки вверх и вниз крутят текст, а не ходят курсором.
  ///
  /// Так листают в Lister Total Commander, во встроенном просмотрщике Far и в
  /// `less`, и просмотрщику это нужно, а редактору нельзя. Разница здесь не
  /// между режимами, а между экранами: в редакторе каретку видно, и `Down` на
  /// строку — правильное поведение. В просмотрщике каретки нет, и пока она
  /// идёт от верхней строки окна к нижней, экран не отвечает ничем — два
  /// десятка нажатий впустую.
  final bool scrollsByArrows;

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

  /// Стрелки, отданные прокрутке. Не в [added]: та общая обоим экранам, а эти
  /// принадлежат только просмотрщику.
  static const Map<CodeShortcutType, List<ShortcutActivator>> _scrolling = {
    CodeShortcutType.scrollLineUp: [SingleActivator(LogicalKeyboardKey.arrowUp)],
    CodeShortcutType.scrollLineDown: [SingleActivator(LogicalKeyboardKey.arrowDown)],
  };

  /// У кого прокрутка стрелки забирает.
  ///
  /// Ход курсора **отпускается**, а не просто перекрывается: назначить стрелку
  /// двум типам сразу и надеяться, что нужный перезапишет другого, значило бы
  /// держаться за порядок значений в `enum` библиотеки. У обоих типов на обеих
  /// её раскладках ровно по одному сочетанию — сама стрелка, — поэтому вместе с
  /// ними не уходит ничего лишнего. `Shift`-, `Alt`- и `Cmd`-стрелки — другие
  /// типы, их это не касается.
  static const Set<CodeShortcutType> _walking = {CodeShortcutType.cursorMoveUp, CodeShortcutType.cursorMoveDown};

  @override
  List<ShortcutActivator>? build(CodeShortcutType type) {
    if (released.contains(type) || find.contains(type)) {
      return const [];
    }

    if (scrollsByArrows) {
      if (_walking.contains(type)) {
        return const [];
      }
      final List<ShortcutActivator>? scrolling = _scrolling[type];
      if (scrolling != null) {
        return scrolling;
      }
    }

    final List<ShortcutActivator>? own = added[type];
    if (own == null) {
      return super.build(type);
    }

    // Добавляем, а не заменяем: своё к тому, что библиотека уже назначила.
    return [...?super.build(type), ...own];
  }
}
