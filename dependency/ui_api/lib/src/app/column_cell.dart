import 'package:flutter/widgets.dart';

import 'package:fc_api/fc_api.dart';

/// Всё, что нужно знать ячейке колонки.
///
/// Значением, а не списком доводов: формат вывода (роадмап, Б3) добавится сюда
/// полем, и ни одна подпись объявления не поменяется.
class ColumnCell {
  const ColumnCell({
    required this.entry,
    this.shown = const [],
    this.naming = const ReferenceFileNaming(),
    this.selected = false,
    this.contentOf,
  });

  /// Строка значением: узлы живут в ядре, а рисуют по эту сторону.
  final FileEntry entry;

  /// Колонки, показанные рядом: колонка имени смотрит, видна ли колонка
  /// расширения, — и только тогда отделяет расширение от имени.
  final List<ColumnSpec> shown;

  /// Показана ли рядом колонка [id].
  bool shows(String id) {
    for (final column in shown) {
      if (column.id == id) {
        return true;
      }
    }
    return false;
  }

  /// Чем имя делится на имя и расширение.
  ///
  /// Расширения у файла нет — есть имя, а расширение это его толкование, и
  /// принадлежит оно тому, кто показывает (`docs/spec/compound-extensions.md`).
  final FileNaming naming;

  /// Строка под курсором активной панели: значок рисуется иначе.
  final bool selected;

  /// Чем открыть байты строки — значку, если правило спрашивает о содержимом.
  final Content Function(FileEntry entry)? contentOf;
}

/// Что показать в ячейке текстом; пусто — ячейка пуста.
typedef ColumnText = String? Function(ColumnCell cell);

/// Своя ячейка — там, где текста мало: значок типа объекта.
typedef ColumnCellBuilder = Widget Function(BuildContext context, ColumnCell cell);

/// Объявленные колонки — экранной половиной.
///
/// Колонка расщеплена надвое общим идентификатором: в ядре заголовок, ширина и
/// **сравнение** (`ColumnSorting`), здесь заголовок, ширина и **ячейка**. Одно
/// и то же объявление модуль регистрирует по разу на каждой стороне: колбэк
/// через границу не поедет (`docs/spec/column-registry.md`, §3.2).
abstract interface class PanelColumns {
  /// Всё объявленное — в порядке объявления.
  List<ColumnSpec> get declared;

  ColumnSpec? find(String id);

  ColumnText? textOf(String id);

  ColumnCellBuilder? builderOf(String id);

  /// Объявленное, переставленное и подправленное раскладкой панели.
  ///
  /// [extra] — колонки, которых просит показанный источник
  /// (`SourceInfo.extraColumns`): их включают поверх раскладки, никуда не
  /// сохраняя.
  ColumnLayout resolve(ColumnLayout layout, {Set<String> extra = const {}});
}
