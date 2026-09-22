import 'package:flutter/widgets.dart';

import 'fc_theme.dart';

/// Плашка: приглушённый фон со скруглёнными углами и полем внутри.
///
/// Ею обведён раздел настроек, и ею же — всё прочее, что стоит в окне
/// **списком**: дерево выбора каталога (`docs/spec/settings-presets.md`, §7).
/// Одна на приложение, а не скопированная: два по-разному скруглённых
/// прямоугольника в одном окне человек видит сразу.
class FcPlate extends StatelessWidget {
  const FcPlate({super.key, required this.child, this.tight = false});

  final Widget child;

  /// Содержимое вплотную к краям, без поля внутри.
  ///
  /// Так стоит **список**: курсор в нём упирается в края плашки — то же общее
  /// правило, по которому строка в панели упирается в её рамку. С полем внутри
  /// курсор висел бы в воздухе, и плашка читалась бы как вторая рамка вокруг
  /// него. Поле остаётся у того, что читается текстом: раздел настроек,
  /// таблица справки.
  ///
  /// Содержимое при этом обрезается по скруглению: иначе подсветка первой
  /// строки вылезала бы за угол.
  final bool tight;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;

    return Container(
      // Во всю ширину: столбец даёт детям их собственную ширину, и плашка
      // облегала бы содержимое — короткий раздел выходил уже длинного, и
      // разделы стояли лесенкой.
      width: double.infinity,
      // Поле со всех сторон одинаковое: содержимое не должно прилипать ни к
      // краю плашки, ни к её скруглению. Списку — наоборот, вплотную (см.
      // [tight]).
      padding: tight ? EdgeInsets.zero : EdgeInsets.all(metrics.dialogPadding),
      decoration: BoxDecoration(
        color: theme.colors.dialogListBackground,
        border: Border.all(color: theme.colors.dialogListBorder, width: metrics.strokeWidth),
        borderRadius: BorderRadius.circular(metrics.panelRadius),
      ),
      child:
          tight
              // Обрезка по **внутреннему** краю, а не по внешнему: содержимое
              // и так стоит внутри обводки, и общая обрезка `Container`
              // прошла бы по её наружной кромке — курсор первой строки ложился
              // бы на угол обводки сверху. Скругление внутри на толщину линии
              // мельче наружного.
              ? ClipRRect(borderRadius: BorderRadius.circular(metrics.panelRadius - metrics.strokeWidth), child: child)
              : child,
    );
  }
}
