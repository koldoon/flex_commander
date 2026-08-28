import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

/// Полоса вверху окна — вместо системной.
///
/// Системной полосы заголовка у окна нет: содержимое занимает его целиком, и
/// фон вверху такой же, как везде, а не светлая накладка. Взамен теряются две
/// вещи, которые полоса давала даром, — их эта и возвращает:
///
/// * окно двигают за неё ([WindowService.startDrag]);
/// * двойное нажатие разворачивает окно и возвращает обратно.
///
/// Светофор macOS остаётся на месте и стоит поверх — это системные кнопки, и
/// нажатия на них сюда не доходят. Поэтому полоса и не ниже светофора: иначе
/// кнопки легли бы на содержимое.
///
/// Рисовать ей нечего: она пустая, и сквозь неё виден фон окна. Появится
/// заголовок или вкладки — станет местом для них.
class WindowTitleBar extends StatelessWidget {
  const WindowTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);

    return GestureDetector(
      // Пустое место тоже тащит окно: полоса вся целиком — ручка.
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => app.window.startDrag(),
      onDoubleTap: app.window.toggleMaximized,
      child: SizedBox(height: FcTheme.of(context).metrics.windowTitleBarHeight),
    );
  }
}
