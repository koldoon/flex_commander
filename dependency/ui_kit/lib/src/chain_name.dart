import 'package:flutter/widgets.dart';

import 'fc_theme.dart';
import 'text_trim.dart';
import 'trimmed_text.dart';

/// Подпись строки-цепочки сжатого дерева: приглушённая голова и яркое имя —
/// `src/main/java/com/acme` (`docs/spec/panel-view-compact-tree.md`, §3, §6).
///
/// Голова — имена поглощённых каталогов, имя — самый глубокий из них, то есть
/// сама строка. Приглушается голова по тому же правилу, что и начало пути в
/// истории адресов ([FcPickList] с `dimPathHead`): важное — в конце.
///
/// Живёт в `fc_ui_kit`, а не в виде панели: ту же подпись возьмёт выбор файла
/// для импорта и экспорта (`FcDirectoryTree`, шаг 2).
class FcChainName extends StatelessWidget {
  const FcChainName({
    super.key,
    required this.head,
    required this.name,
    required this.style,
    required this.headStyle,
    this.nameSide = FcTrimSide.tail,
  });

  /// Имена поглощённых каталогов через `/`, без завершающей черты.
  final String head;

  final String name;

  /// Начертание имени.
  final TextStyle style;

  /// Начертание головы — приглушённое.
  final TextStyle headStyle;

  /// Как резать имя, когда не влезает и оно одно: по настройке обрезки имён.
  final FcTrimSide nameSide;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final fitted = fitChainName(
        head: head,
        name: name,
        style: FcTheme.effective(context, style),
        headStyle: FcTheme.effective(context, headStyle),
        maxWidth: constraints.maxWidth,
        scaler: MediaQuery.textScalerOf(context),
        nameSide: nameSide,
      );
      return fcTooltipIf(
        context,
        trimmed: fitted.trimmed,
        message: '$head/$name',
        child: Text.rich(
          TextSpan(
            children: [
              if (fitted.head.isNotEmpty) TextSpan(text: fitted.head, style: headStyle),
              TextSpan(text: fitted.name, style: style),
            ],
          ),
          maxLines: 1,
          softWrap: false,
          // Хвост имени режет `ellipsis` — так же, как у обычной строки дерева;
          // голову и середину отрезали мы сами.
          overflow: TextOverflow.ellipsis,
        ),
      );
    },
  );
}

/// Что показать подписью цепочки в [maxWidth] — по ступеням (§6):
///
/// 1. всё целиком: `src/main/java/com/acme`;
/// 2. голова, обрезанная слева по целым звеньям: `…/com/acme` — конец головы
///    ближе к имени и потому важнее, а звено с дырой читалось бы другим именем;
/// 3. одно имя, обрезанное по [nameSide], — как у строки без цепочки.
///
/// Голова возвращается вместе с завершающей `/`: это часть того, что рисуется.
/// [trimmed] — обрезано ли хоть что-то: тогда подпись договаривает подсказка.
({String head, String name, bool trimmed}) fitChainName({
  required String head,
  required String name,
  required TextStyle style,
  required TextStyle headStyle,
  required double maxWidth,
  required TextScaler scaler,
  FcTrimSide nameSide = FcTrimSide.tail,
}) {
  final whole = '$head/';
  if (maxWidth.isInfinite || maxWidth <= 0) {
    return (head: whole, name: name, trimmed: false);
  }

  final nameWidth = textWidthOf(name, style, scaler);
  if (textWidthOf(whole, headStyle, scaler) + nameWidth <= maxWidth) {
    return (head: whole, name: name, trimmed: false);
  }

  // Звенья головы отбрасываются слева, пока остаток с именем не влезет.
  final parts = head.split('/');
  for (var skip = 1; skip <= parts.length; skip++) {
    final shown = skip == parts.length ? '…/' : '…/${parts.skip(skip).join('/')}/';
    if (textWidthOf(shown, headStyle, scaler) + nameWidth <= maxWidth) {
      return (head: shown, name: name, trimmed: true);
    }
  }

  // Не влезает даже «…/имя» — остаётся одно имя, как у обычной строки.
  final shown = nameSide == FcTrimSide.middle ? trimTextMiddle(name, style, maxWidth, scaler) : name;
  return (head: '', name: shown, trimmed: true);
}
