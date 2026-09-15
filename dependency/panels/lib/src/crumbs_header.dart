import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

/// Имя заголовка со звеньями.
const String crumbsHeaderId = 'crumbs';

/// Звено адреса: что показать и куда по нему идти.
class PathCrumb {
  const PathCrumb(this.label, this.path);

  /// Что видно: имя каталога, корень или `схема://хост`.
  final String label;

  /// Куда ведёт: путь целиком, а не имя звена.
  final String path;
}

/// Разобрать адрес на звенья; пусто — это не адрес.
///
/// Первое звено — **корень источника**, а не корень диска: у `ssh://` это
/// `ssh://user@host`, у локального пути — `/`. Архив звеном не выделяется: для
/// панели это каталог (`docs/spec/panel-crumbs.md`, §2).
///
/// Текст без разделителей звеньями не становится: заголовок, выставленный
/// командой («найдено 12»), — подпись, а не адрес, и делить её не на что.
List<PathCrumb> crumbsOf(String address) {
  final text = pathWithoutTrailingSlash(address.trim());
  if (text.isEmpty) {
    return const [];
  }

  final scheme = text.indexOf('://');
  final String root;
  final String rest;
  if (scheme >= 0) {
    final afterScheme = scheme + 3;
    final slash = text.indexOf('/', afterScheme);
    root = slash < 0 ? text : text.substring(0, slash);
    rest = slash < 0 ? '' : text.substring(slash + 1);
  } else if (text.startsWith('/')) {
    root = '/';
    rest = text.substring(1);
  } else {
    // Ни схемы, ни корня — это не путь.
    return const [];
  }

  final crumbs = [PathCrumb(root, root)];
  var walked = root;
  for (final name in rest.split('/')) {
    if (name.isEmpty) {
      continue;
    }
    walked = walked.endsWith('/') ? '$walked$name' : '$walked/$name';
    crumbs.add(PathCrumb(name, walked));
  }
  return crumbs;
}

/// Адрес панели звеньями: `Users › koldoon › dev`.
///
/// Спецификация — `docs/spec/panel-crumbs.md`.
class CrumbsHeader extends StatelessWidget {
  const CrumbsHeader({super.key, required this.view});

  final PanelHeaderView view;

  /// Разделитель звеньев.
  static const String separator = ' › ';

  /// Чем показана свёрнутая середина.
  static const String ellipsis = '…';

  @override
  Widget build(BuildContext context) {
    final crumbs = crumbsOf(view.text);
    // Не адрес — строкой, как обычно: делить нечего (§2).
    if (crumbs.isEmpty) {
      return FcPathText(text: view.text, width: view.width, style: view.style);
    }

    final theme = FcTheme.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final dim = view.style.copyWith(color: theme.colors.secondaryText);
    final shown = _fit(crumbs, dim, scaler);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) Text(separator, style: dim),
          // Гнётся **только последнее** звено, остальные стоят во всю свою
          // ширину. Гибкими были все — и ряд делил место поровну: длинные
          // имена обрезались многоточием, хотя рядом оставалась пустота, а
          // плашка не дорастала до краёв (поймано живьём).
          //
          // Последнему гибкость нужна как предохранитель: свёртка обязана
          // оставить его целиком (§3), и когда даже `корень › … › последнее`
          // шире плашки, обрезать остаётся только его.
          if (shown[i] case final crumb?)
            if (i == shown.length - 1)
              // Последнее — ярко, всё до него приглушённо: строки различаются
              // концом (§4).
              Flexible(child: _Crumb(crumb: crumb, panel: view.panel, style: view.style))
            else
              _Crumb(crumb: crumb, panel: view.panel, style: dim)
          else
            // Свёрнутая середина молчит: нажатие обещало бы то, чего нет.
            // Полный путь виден подсказкой плашки (§3).
            Text(ellipsis, style: dim),
        ],
      ],
    );
  }

  /// Что влезет: все звенья, а если нет — первое, многоточие и хвост.
  ///
  /// null в списке — свёрнутая середина. Меряется тем же стилем, каким будет
  /// набрано: мерить не то, что рисуется, значит промахнуться на разрядку
  /// окружения.
  List<PathCrumb?> _fit(List<PathCrumb> crumbs, TextStyle style, TextScaler scaler) {
    double widthOf(Iterable<String> parts) => textWidthOf(parts.join(separator), style, scaler);

    if (widthOf(crumbs.map((crumb) => crumb.label)) <= view.width) {
      return [...crumbs];
    }

    // С хвоста: последнее звено важнее всех, первое обязано остаться.
    final root = crumbs.first;
    final tail = <PathCrumb>[];
    for (final crumb in crumbs.skip(1).toList().reversed) {
      final parts = [root.label, ellipsis, crumb.label, ...tail.map((c) => c.label)];
      if (widthOf(parts) > view.width && tail.isNotEmpty) {
        break;
      }
      tail.insert(0, crumb);
    }

    return [root, if (tail.length < crumbs.length - 1) null, ...tail];
  }
}

/// Одно звено: нажимается и ведёт.
class _Crumb extends StatefulWidget {
  const _Crumb({required this.crumb, required this.panel, required this.style});

  final PathCrumb crumb;
  final Session panel;
  final TextStyle style;

  @override
  State<_Crumb> createState() => _CrumbState();
}

class _CrumbState extends State<_Crumb> {
  /// Мышь над этим звеном.
  ///
  /// Подчёркиванием, а не цветом: цвет здесь занят — им сказано, какое звено
  /// последнее (§4), — и вторая роль у того же цвета читалась бы как первая.
  /// Курсор-палец говорит «сюда можно нажать», подчёркивание — «вот на что
  /// попадёт нажатие»: в ряду из коротких слов это разные сведения.
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Обычный переход панели, а не особый случай: значит шаг попадает в
        // историю сам собой (§5). Активной панель делает нажатие в ней — тем
        // же обработчиком, что и щелчок по списку файлов.
        onTap: () => unawaited(widget.panel.openPath(widget.crumb.path)),
        child: Text(
          widget.crumb.label,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: _hovered ? widget.style.copyWith(decoration: TextDecoration.underline) : widget.style,
        ),
      ),
    );
  }
}
