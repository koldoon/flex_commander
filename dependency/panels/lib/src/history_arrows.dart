import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';

/// «Назад» и «вперёд» в шапке своей панели
/// (`docs/spec/session-history.md`, §9).
///
/// История у каждой панели своя, и кнопка стоит там же, где видно, куда она
/// ведёт. Зовут они **сессию**, а не команду: команды приносит модуль
/// навигации, а панель о нём не знает и знать не должна.
class HistoryArrows extends StatelessWidget {
  const HistoryArrows({super.key, required this.panel});

  final Session panel;

  /// Сколько места они займут.
  ///
  /// Объявляется наружу, потому что плашка обрезает путь **сама** и обязана
  /// знать, сколько у неё отняли: иначе она отмерит путь по всей плашке, и
  /// конец пути уйдёт за край (`docs/spec/session-history.md`, §9). Та же
  /// величина держит и сам ряд — расходиться им негде.
  static double widthOf(FcTheme theme) => theme.metrics.fontSize * 2 + theme.metrics.labelPadding;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);

    return ListenableBuilder(
      listenable: panel,
      builder:
          (context, _) => SizedBox(
            width: widthOf(theme),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Arrow(
                  icon: theme.icons.angleLeft,
                  hint: context.strings.tr('Back'),
                  onTap: panel.canGoBack ? () => panel.goBack() : null,
                ),
                SizedBox(width: theme.metrics.labelPadding),
                _Arrow(
                  icon: theme.icons.angleRight,
                  hint: context.strings.tr('Forward'),
                  onTap: panel.canGoForward ? () => panel.goForward() : null,
                ),
              ],
            ),
          ),
    );
  }
}

/// Одна стрелка: значок, который можно нажать, пока есть куда идти.
class _Arrow extends StatelessWidget {
  const _Arrow({required this.icon, required this.hint, required this.onTap});

  final IconData icon;
  final String hint;

  /// null — идти некуда: стрелка приглушена и нажатий не берёт. Нажатие без
  /// ответа — ошибка, а исчезнувшая стрелка дёргала бы плашку на каждом шаге
  /// (`docs/widgets.md`).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final colors = theme.colors;
    final live = onTap != null;

    return MouseRegion(
      cursor: live ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Tooltip(
          message: hint,
          waitDuration: const Duration(milliseconds: 600),
          child: Icon(icon, size: theme.metrics.fontSize, color: live ? colors.pathText : colors.pathInactiveText),
        ),
      ),
    );
  }
}
