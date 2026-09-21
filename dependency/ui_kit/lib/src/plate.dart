import 'package:flutter/widgets.dart';

import 'fc_theme.dart';

/// Плашка: приглушённый фон со скруглёнными углами и полем внутри.
///
/// Ею обведён раздел настроек, и ею же — всё прочее, что стоит в окне
/// **списком**: дерево выбора каталога (`docs/spec/settings-presets.md`, §7).
/// Одна на приложение, а не скопированная: два по-разному скруглённых
/// прямоугольника в одном окне человек видит сразу.
class FcPlate extends StatelessWidget {
  const FcPlate({super.key, required this.child});

  final Widget child;

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
      // краю плашки, ни к её скруглению.
      padding: EdgeInsets.all(metrics.dialogPadding),
      decoration: BoxDecoration(
        color: theme.colors.dialogListBackground,
        border: Border.all(color: theme.colors.dialogListBorder, width: metrics.strokeWidth),
        borderRadius: BorderRadius.circular(metrics.panelRadius),
      ),
      child: child,
    );
  }
}
