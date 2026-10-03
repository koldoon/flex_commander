import 'dart:typed_data';
import 'dart:ui';

/// Разбор и отрисовка PDF силами системы.
///
/// Документ живёт **там**, где его разобрали, — у Dart только ручка на него:
/// страниц сотни, а рисовать надо только видимые и того размера, каким их
/// показывают сейчас (`docs/spec/pdf-viewer.md`, §3).
///
/// Службы нет — просмотрщик отказывает словами и предлагает открыть файл
/// системой.
abstract interface class SystemPdf {
  /// Разобрать документ.
  ///
  /// **Байтами, а не путём**: так PDF открывается из архива и с сервера тем же
  /// путём, что и с диска. null — не PDF или поломан так, что система его не
  /// разобрала.
  Future<SystemPdfDocument?> open(Uint8List bytes);
}

/// Разобранный документ — ручка на него.
abstract interface class SystemPdfDocument {
  /// Размеры страниц в пунктах — **показанные**: по `cropBox` и с учётом
  /// поворота страницы. О повороте Dart не думает вовсе: ему приходят
  /// прямоугольные страницы и доли от них.
  List<Size> get pages;

  /// Заперт ли документ паролем. Запертый не рисуется.
  bool get locked;

  /// Отпереть паролем. `true` — подошёл: документ отперт, а [pages] — уже
  /// отпертого (у запертого система может не отдать их вовсе).
  Future<bool> unlock(String password);

  /// Нарисовать страницу [page] шириной [width] точек; `png`.
  ///
  /// null — не вышло: страницы нет или документ уже закрыт.
  Future<Uint8List?> render(int page, int width);

  /// Найти строку во всём документе, по порядку страниц.
  Future<List<PdfMatch>> find(String text, {required bool caseSensitive});

  /// Оглавление — плоско, в порядке документа; пусто — его нет
  /// (`docs/spec/pdf-viewer.md`, §16).
  Future<List<PdfOutlineItem>> outline();

  /// Ссылки страницы [page].
  Future<List<PdfLink>> links(int page);

  /// Весь текст документа; пусто — текста нет (скан).
  ///
  /// Дорого — на трёхстах страницах больше секунды, — поэтому только по
  /// просьбе, а не при открытии.
  Future<String> text();

  /// Отпустить документ. После этого ручка не годится ни на что.
  Future<void> close();
}

/// Одно найденное место.
class PdfMatch {
  const PdfMatch({required this.page, required this.rects});

  /// Номер страницы, с нуля.
  final int page;

  /// Где на странице — в долях её показанных сторон, отсчёт сверху слева.
  ///
  /// Прямоугольников бывает несколько: найденное переносится на следующую
  /// строку, и каждой строке свой.
  final List<Rect> rects;

  /// Охватывающий прямоугольник — к нему подводится показ.
  Rect get bounds => rects.reduce((a, b) => a.expandToInclude(b));
}

/// Место в документе: страница и где на ней.
class PdfTarget {
  const PdfTarget(this.page, {this.top});

  /// Номер страницы, с нуля.
  final int page;

  /// Доля высоты показанной страницы, отсчёт сверху; null — начало страницы.
  final double? top;

  @override
  bool operator ==(Object other) => other is PdfTarget && other.page == page && other.top == top;

  @override
  int get hashCode => Object.hash(page, top);

  @override
  String toString() => 'PdfTarget($page, $top)';
}

/// Заголовок оглавления.
class PdfOutlineItem {
  const PdfOutlineItem({required this.depth, required this.title, required this.target});

  /// Уровень вложенности, с нуля.
  final int depth;

  final String title;

  final PdfTarget target;
}

/// Ссылка на странице: либо место в документе, либо внешний адрес.
class PdfLink {
  const PdfLink({required this.rect, this.target, this.url})
    : assert((target == null) != (url == null), 'ссылка ведёт либо внутрь, либо наружу');

  /// Где на странице — в долях её показанных сторон, отсчёт сверху слева.
  final Rect rect;

  final PdfTarget? target;

  /// Внешний адрес: `https://…`, `mailto:…`.
  final String? url;
}
