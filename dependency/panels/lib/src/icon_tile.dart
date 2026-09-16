import 'dart:math' as math;

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'file_type_icon.dart';

/// Одна плитка сетки: значок, под ним имя в две строки.
///
/// То же, чем `FileTableRow` служит списку, — но подсветка устроена иначе.
/// Строка занимает всю ширину, и красить её фоном целиком естественно; плитка
/// же стоит в сетке, и залитый прямоугольник в четверть панели читается
/// пятном. Поэтому курсор и пометка живут **плашками**: скруглённая плашка под
/// значком и такая же под именем, облегающая текст
/// (`docs/spec/panel-view-icons.md`, §4).
class IconTile extends StatelessWidget {
  const IconTile({
    super.key,
    required this.entry,
    required this.iconSize,
    required this.nameHeight,
    required this.marked,
    required this.underCursor,
    required this.panelActive,
    required this.width,
    this.contentOf,
    this.onTap,
  });

  final FileEntry entry;

  /// Сторона значка в точках — своя величина, не размер строки списка.
  final double iconSize;

  /// Место под имя: две строки всегда, влезло оно в одну или нет.
  ///
  /// Иначе высота плитки зависела бы от имени, а на её постоянстве держится
  /// ленивость сетки (`docs/spec/panel-view-icons.md`, §5).
  final double nameHeight;

  final bool marked;
  final bool underCursor;
  final bool panelActive;

  /// Ширина плитки: по ней режется имя.
  final double width;

  final Content Function(FileEntry entry)? contentOf;

  final VoidCallback? onTap;

  bool get _selected => underCursor && panelActive;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final colors = theme.colors;
    final metrics = theme.metrics;
    final style = _selected ? nameStyle(theme).copyWith(color: colors.cursorText) : nameStyle(theme);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      // Во всю ширину и по центру: [FcTrimmedText] ширину берёт только для
      // мерки, а рисуется по содержимому, — и без этого короткое имя утащило бы
      // за собой всю плитку к левому краю, а столбцы перестали бы читаться
      // столбцами.
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: metrics.cellPadding, vertical: metrics.rowGap),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _icon(theme),
              SizedBox(height: metrics.rowGap),
              SizedBox(
                // Место под полосу пометки отведено **всегда**, помечен объект
                // или нет: иначе пометка двигала бы имя вниз, а она не вправе
                // двигать ничего.
                height: markRoom(metrics) + nameHeight,
                child: Align(alignment: Alignment.topCenter, child: _name(context, theme, style)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Значок на плашке — под курсором; иначе просто значок.
  ///
  /// Плашка чуть больше самого значка: её поле — тот же просвет, каким значок
  /// отбит от имени в строке списка.
  Widget _icon(FcTheme theme) {
    final metrics = theme.metrics;
    // Значок берётся у той же службы, что и в списке: плитка своего рисования
    // не заводит вовсе, поэтому миниатюры потом не потребуют её правок
    // (`docs/spec/file-icons.md`).
    final Widget glyph = FileTypeIcon(
      entry: entry,
      selected: _selected,
      contentOf: contentOf,
      size: iconSize,
      // Дыры на месте значка в плитке быть не должно: у файла без правила
      // рисуется лист бумаги.
      fillsBlank: true,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        // Своей роли цвета этап не заводит: плашка панели — это и есть
        // «поверхность поверх фона», а новая роль стоила бы правки макета
        // (`docs/spec/design-system.md`, §8).
        color: _selected ? theme.colors.panelBackground : null,
        borderRadius: BorderRadius.circular(metrics.panelRadius),
      ),
      child: Padding(
        padding: EdgeInsets.all(metrics.iconGap),
        child: SizedBox(width: iconSize, height: iconSize, child: Center(child: glyph)),
      ),
    );
  }

  /// Имя в плашке, облегающей текст.
  ///
  /// Короткое имя — короткая плашка: залитая во всю ширину полоса под коротким
  /// именем читалась бы обрубком ряда, а не пометкой объекта.
  Widget _name(BuildContext context, FcTheme theme, TextStyle style) {
    final metrics = theme.metrics;
    final colors = theme.colors;
    final plate =
        _selected
            ? colors.cursorBackground
            : marked
            ? colors.markedBackground
            : null;

    // Ровно столько, сколько текст и получит: поля плитки и поля плашки.
    //
    // Пометка на это число не влияет вовсе — см. ниже, где рисуется её полоса.
    final room = width - metrics.cellPadding * 4;
    // Плашка облегает имя: не всю отведённую ширину, а самую длинную строку
    // набранного. Короткое имя — короткая плашка; имя в две строки — плашка по
    // длинной из них, а не во всю плитку.
    final taken = math.min(
      room,
      textWidestLine(
        entry.name,
        FcTheme.effective(context, style),
        room,
        MediaQuery.textScalerOf(context),
        maxLines: nameLines,
      ),
    );

    final Widget text = Padding(
      padding: EdgeInsets.symmetric(horizontal: metrics.cellPadding),
      child: SizedBox(
        // Ужать до собственной длинной строки безопасно: перенос жадный, и
        // строки лягут теми же.
        width: taken,
        child: FcTrimmedText(
          text: entry.name,
          style: style,
          width: room,
          textAlign: TextAlign.center,
          maxLines: nameLines,
        ),
      ),
    );

    if (plate == null && !marked) {
      // С тем же отступом сверху, что и у помеченного: место под полосу
      // отведено всем, иначе имена стояли бы на разной высоте.
      return Padding(padding: EdgeInsets.only(top: markRoom(metrics)), child: text);
    }

    // Полоса пометки — **над именем**, поверх плашки, во всю её ширину.
    //
    // Места у имени она при этом не отнимает: плашка на ту же высоту растёт
    // вверх, а место над ней отведено заранее — и текст остаётся ровно там же,
    // где стоял до пометки. Отними полоса место изнутри, буквы прыгали бы вниз
    // ровно в тот миг, когда на плитку смотрят
    // (`docs/spec/panel-view-icons.md`, §4).
    final grown = marked ? markRoom(metrics) : 0.0;

    final Widget plated = ClipRRect(
      borderRadius: BorderRadius.circular(metrics.panelRadius),
      child: DecoratedBox(
        decoration: BoxDecoration(color: plate),
        child: Stack(
          children: [
            Padding(padding: EdgeInsets.only(top: grown), child: text),
            if (marked)
              Positioned(
                left: 0,
                right: 0,
                // По краю плашки, а отбивка — только снизу, от букв: сверху
                // плашка её и так держит.
                top: 0,
                height: metrics.markedBarWidth,
                child: ColoredBox(color: colors.markedBar),
              ),
          ],
        ),
      ),
    );

    // Непомеченное имя опускается ровно на столько, сколько у помеченного
    // занимает полоса: у обоих оно оказывается на одной высоте, а плашка у
    // помеченного вырастает вверх, а не съедает строку.
    return marked ? plated : Padding(padding: EdgeInsets.only(top: markRoom(metrics)), child: plated);
  }

  /// Сколько места отведено полосе пометки: она сама и её отбивка от букв.
  static double markRoom(FcMetrics metrics) => metrics.markedBarWidth + metrics.markedBarGap;

  /// Чем набрано имя под значком: **обычным набором, а не моноширинным**.
  ///
  /// Моноширинный полезен в таблице — им держатся столбцы и совпадают разряды
  /// размеров; под значком столбцов нет, а читаемость есть, и пропорциональный
  /// набор её прибавляет. Спрашивается в одном месте: тем же начертанием вид
  /// меряет самое длинное имя и высоту двух строк, и разойтись им нельзя.
  static TextStyle nameStyle(FcTheme theme) => theme.uiStyle;

  /// Имя занимает две строки, как в Finder: одной мало половине снимков с
  /// камеры, а третья отнимает у сетки ряд.
  static const int nameLines = 2;

  /// Высота плитки — поле, плашка значка, просвет, две строки имени.
  ///
  /// Считается в одном месте: по ней же ищут плитку под указателем и место
  /// броска, а это три обычных промаха на один просвет.
  static double height(FcMetrics metrics, double iconSize, double nameHeight) =>
      metrics.rowGap * 2 + iconSize + metrics.iconGap * 2 + metrics.rowGap + markRoom(metrics) + nameHeight;
}
