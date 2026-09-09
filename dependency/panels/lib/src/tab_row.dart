import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'panels_settings.dart';

/// Ряд вкладок над панелью (`docs/spec/panel-tabs.md`, §6).
///
/// Рисует его модуль панелей: ряд — часть того, чем панели показываются, и
/// шеллу о вкладках знать незачем.
///
/// **Пока вкладка одна, ряда нет.** Полоса, которая ничего не выбирает, отняла
/// бы строку у списка файлов; кому нужна кнопка «плюс» под рукой — есть
/// настройка «показывать всегда».
class PanelTabRow extends StatelessWidget {
  const PanelTabRow({super.key, required this.panel, required this.settings});

  final Panel panel;

  final PanelsSettings Function() settings;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.read(context);
    final side = app.view.positionOf(panel);
    if (side == null) {
      return const SizedBox.shrink();
    }

    // Две подписки, и обе нужны. Внешняя — на приложение: от неё меняется
    // **состав** ряда. Внутренняя — на сами вкладки: от них меняются
    // заголовки, а собирается она заново на каждый состав, иначе заведённую
    // только что вкладку никто не слушает и её имя застывает тем, каким было
    // при заведении.
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final tabs = app.tabsAt(side);
        if (tabs.length < 2 && !settings().tabsAlwaysVisible) {
          return const SizedBox.shrink();
        }
        return ListenableBuilder(
          listenable: Listenable.merge([for (final tab in tabs) tab.panel]),
          builder: (context, _) => _row(context, app, tabs),
        );
      },
    );
  }

  Widget _row(BuildContext context, Application app, List<PanelTab> tabs) {
    final metrics = FcTheme.of(context).metrics;
    return SizedBox(
      height: metrics.headerRowHeight,
      child: Row(
        children: [
          for (final tab in tabs) ...[
            if (!identical(tab, tabs.first)) SizedBox(width: metrics.strokeWidth),
            Flexible(
              child: _Tab(
                title: titleOf(tab, tabs),
                pinned: tab.pinned,
                current: _isShown(app, tab),
                onTap: () => app.activate(tab.panel),
                onClose: tabs.length > 1 ? () => app.closeTab(tab) : null,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Показана ли эта вкладка в своей стороне.
  static bool _isShown(Application app, PanelTab tab) {
    final side = app.view.positionOf(tab.panel);
    return side != null && identical(app.view.panelAt(side), tab.panel);
  }

  /// Заголовок вкладки: имя каталога, а совпавшие — с именем родителя.
  ///
  /// Путь длинный, а рядом их пять; полный путь — подсказкой. Разводятся
  /// **только совпавшие**: остальные остаются короткими
  /// (`docs/spec/panel-tabs.md`, §5).
  static String titleOf(PanelTab tab, List<PanelTab> among) {
    final name = _nameOf(tab);
    final twins = among.where((other) => !identical(other, tab) && _nameOf(other) == name);
    if (twins.isEmpty) {
      return name;
    }
    final parent = _parentOf(tab);
    return parent.isEmpty ? name : '$name — $parent';
  }

  static String _nameOf(PanelTab tab) {
    final panel = tab.panel;
    final header = panel.headerText;
    if (header != null && header.isNotEmpty) {
      return header;
    }
    final name = panel.directoryName;
    return name.isEmpty ? (panel.currentPath.isEmpty ? '/' : panel.currentPath) : name;
  }

  static String _parentOf(PanelTab tab) {
    final path = tab.panel.currentPath;
    final at = path.lastIndexOf('/');
    if (at <= 0) {
      return '';
    }
    final parent = path.substring(0, at);
    final from = parent.lastIndexOf('/');
    return from < 0 ? parent : parent.substring(from + 1);
  }
}

/// Одна вкладка: заголовок, знак закрепления и крестик.
class _Tab extends StatelessWidget {
  const _Tab({
    required this.title,
    required this.pinned,
    required this.current,
    required this.onTap,
    required this.onClose,
  });

  final String title;
  final bool pinned;
  final bool current;
  final VoidCallback onTap;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final colors = theme.colors;
    final metrics = theme.metrics;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      // Средняя кнопка закрывает — привычка браузера, и стоит она недорого.
      onTertiaryTapUp: (_) => onClose?.call(),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: metrics.cellPadding * 2),
        decoration: BoxDecoration(
          color: current ? colors.pathBackground : colors.panelBackground,
          border: Border.all(color: current ? colors.pathBorder : colors.panelBorder, width: metrics.strokeWidth),
          borderRadius: BorderRadius.circular(metrics.inputRadius),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (pinned) ...[Text('•', style: theme.pathStyle), SizedBox(width: metrics.cellPadding)],
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: current ? theme.pathStyle : theme.statusStyle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
