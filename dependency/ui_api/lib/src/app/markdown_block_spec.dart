import 'package:flutter/widgets.dart';

/// Чем рисуется огороженная врезка ```` ```<язык> ```` в свёрстанном markdown.
///
/// Объявляет модуль, а спрашивает тот, кто показывает документ, — ровно так же,
/// как с просмотрщиками: ядро только складывает и упорядочивает, а решать, чей
/// это язык, ему нечем.
///
/// Ради этого реестр и заведён: диаграмму рисует **отдельный** модуль
/// (`docs/spec/mermaid.md`), ничего не зная о просмотрщике, а просмотрщик —
/// ничего о диаграммах. Устройство и причины — `docs/spec/markdown-viewer.md`,
/// §2.
class MarkdownBlockSpec {
  const MarkdownBlockSpec({
    required this.id,
    required this.title,
    required this.accepts,
    required this.build,
    this.priority = 0,
  });

  /// Устойчивое имя: `mermaid`, `plantuml`. Уходит в настройки и в отказы.
  final String id;

  /// Название для человека — «Mermaid diagrams». По-английски: это ключ
  /// перевода, русский приходит словарём модуля.
  final String title;

  /// Больше — раньше спрашивают. При равном — порядок объявления модулей.
  final int priority;

  /// Берётся ли за такой язык. Имя уже приведено к нижнему регистру.
  ///
  /// Решение **по имени**, а не по содержимому — тот же раздел обязанностей,
  /// что у просмотрщика: `accepts` отвечает «моё ли это по имени», а
  /// [MarkdownBlockRefused] — «моё, но вот беда». Иначе содержимое разбиралось
  /// бы дважды: один раз чтобы согласиться, второй — чтобы нарисовать.
  final bool Function(String language) accepts;

  /// Нарисовать врезку.
  ///
  /// Работа **синхронная**: врезок в документе немного, а показ, начинающийся
  /// с пустого места, хуже показа, начинающегося сразу. Долгое виджет делает
  /// внутри себя сам.
  ///
  /// [MarkdownBlockDeclined] — «это не мой язык», спрашивают следующего;
  /// [MarkdownBlockRefused] — взялся и не смог, и тогда показ рисует исходный
  /// текст врезки с причиной словами.
  final Widget Function(BuildContext context, MarkdownBlockRequest request) build;
}

/// Что рисуем.
class MarkdownBlockRequest {
  const MarkdownBlockRequest({
    required this.language,
    required this.source,
    this.metadata = '',
    this.maxWidth = double.infinity,
  });

  /// Первое слово info-строки, в нижнем регистре: `mermaid`.
  final String language;

  /// Текст врезки как он написан — без ограждений и без хвостового перевода
  /// строки, который добавляет разбор.
  final String source;

  /// Хвост info-строки: ```` ```mermaid theme=neutral ```` даёт
  /// `theme=neutral`. Пусто — его не было.
  final String metadata;

  /// Сколько места дают по ширине; `infinity` — меряют по содержимому.
  ///
  /// Доводом, а не через `LayoutBuilder` у рисующего: диаграмме ширина нужна
  /// **до** раскладки, иначе её не во что вписывать. Ставит `LayoutBuilder`
  /// показ — один раз и одинаково для всех.
  final double maxWidth;
}

/// Взялся и не смог: причину увидит человек, на месте самой врезки.
class MarkdownBlockRefused implements Exception {
  const MarkdownBlockRefused(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// Ошибся, взявшись: это не мой язык — спрашивайте следующего.
///
/// Человеку не показывается ничего: он о такой ошибке знать не должен.
class MarkdownBlockDeclined implements Exception {
  const MarkdownBlockDeclined();

  @override
  String toString() => 'MarkdownBlockDeclined';
}
