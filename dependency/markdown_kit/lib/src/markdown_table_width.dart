import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Ширина колонки таблицы — по её содержимому, а не поровну.
///
/// Поровну плохо тем, что колонка «Да/Нет» получает столько же места, сколько
/// колонка с описанием на три строки: одна стоит полупустой, другая переносится
/// впятеро чаще, чем нужно.
///
/// Считаются две ширины на колонку — общепринятая пара из автоматической
/// раскладки таблиц CSS (CSS 2.1, §17.5.2.2):
///
/// * **наименьшая** — ширина самого длинного слова: уже неё колонку сжимать
///   нельзя, слово порвётся;
/// * **наибольшая** — ширина содержимого без единого переноса.
///
/// Дальше распределяет сам `RenderTable`, и делает он ровно то, что нужно:
/// начинает с наибольших, а если таблица не влезла — снимает лишнее
/// пропорционально, упирая каждую колонку в её наименьшую. Короткая колонка
/// упирается сразу и дальше не сжимается, а длинная забирает недостачу на себя.
///
/// Вес для распределения остатка — наибольшая ширина: если места **больше**,
/// чем нужно, лишнее достаётся колонкам по их содержимому, а не поровну.
///
/// Почему свой класс, а не готовый `IntrinsicColumnWidth`, который считает то
/// же самое: показ markdown смотрит на тип ширины и, увидев его, заворачивает
/// таблицу в горизонтальную прокрутку (`builder.dart:448`) — то есть даёт ей
/// бесконечную ширину, и длинный текст не переносится вовсе. Этот класс той
/// проверке не отвечает, и таблица остаётся в отведённой ширине
/// (`docs/spec/markdown-viewer.md`, §6).
class FcContentColumnWidth extends TableColumnWidth {
  const FcContentColumnWidth();

  @override
  double minIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) =>
      _widest(cells, (cell) => cell.getMinIntrinsicWidth(double.infinity));

  @override
  double maxIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) =>
      _widest(cells, (cell) => cell.getMaxIntrinsicWidth(double.infinity));

  @override
  double? flex(Iterable<RenderBox> cells) {
    final wanted = maxIntrinsicWidth(cells, double.infinity);

    // Пустой колонке веса не даём: `RenderTable` требует веса строго больше
    // нуля, а делить между пустыми колонками всё равно нечего.
    return wanted > 0 ? wanted : null;
  }

  static double _widest(Iterable<RenderBox> cells, double Function(RenderBox cell) of) {
    var widest = 0.0;
    for (final cell in cells) {
      widest = math.max(widest, of(cell));
    }

    return widest;
  }

  @override
  String toString() => 'FcContentColumnWidth()';
}
