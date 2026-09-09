import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'panel_row.dart';

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
/// **В ней живёт ряд открытых наборов** (`docs/spec/panel-sessions.md`, §3) —
/// то самое, ради чего полоса и заводилась пустой
/// (`docs/spec/window-chrome.md`, §7). Ряд прижат к правому краю, а слева от
/// него полоса держит два свободных места: под светофор и под ручку, за
/// которую окно таскают. Тащить можно и за сам ряд: записи ловят нажатия, а
/// протяжка достаётся полосе — как вкладка браузера.
class WindowTitleBar extends StatelessWidget {
  const WindowTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final metrics = FcTheme.of(context).metrics;

    return GestureDetector(
      // Протяжка тащит окно откуда угодно — в том числе с записи ряда: она
      // ловит нажатия, а движение отдаёт полосе, как вкладка браузера.
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => app.window.startDrag(),
      child: SizedBox(
        height: metrics.windowTitleBarHeight,
        child: Stack(
          children: [
            // Двойное нажатие — **под** рядом, а не над ним и не вокруг: пока
            // оно висело общим предком, всякое нажатие по записи ждало срока
            // двойного (300 мс) и отвечало с опозданием. Под рядом оно
            // достаётся только пустым местам полосы — там оно и нужно.
            Positioned.fill(
              child: GestureDetector(behavior: HitTestBehavior.opaque, onDoubleTap: app.window.toggleMaximized),
            ),
            Row(
              children: [
                // Место светофора и свободная ручка за ним: ряд начинается
                // только здесь, чтобы не залезть на системные кнопки и не
                // оставить окно без места, за которое его берут.
                SizedBox(width: metrics.windowControlsWidth + metrics.windowDragHandleWidth),
                Expanded(
                  child: Padding(
                    // Справа ряд кончается там же, где панели под ним: поле
                    // окна одно на всё содержимое.
                    padding: EdgeInsets.only(right: metrics.windowSidePadding),
                    // И опущен на оптический сдвиг: середина светофора ниже
                    // середины полосы, а равняться ряд должен по нему.
                    // Сдвигом, а не полем: разметку он не меняет, и высота
                    // полосы остаётся ровно той, что назначила тема.
                    child: Transform.translate(
                      offset: Offset(0, metrics.windowTitleBarContentNudge),
                      child: const PanelRow(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
