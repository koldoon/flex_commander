import 'package:flutter/widgets.dart';

import 'fc_theme.dart';

/// Тело окна: содержимое и ряд кнопок под ним.
///
/// Окно состоит из трёх зон — полоса заголовка, содержимое, ряд кнопок.
/// Первую рисует рама, остальные две — здесь. Прибиты к своим краям обе
/// крайние, растягивается только середина (`docs/spec/dialog-body.md`).
///
/// **Прокрутка живёт тут, а не в раме.** Рамная уносила бы вместе с
/// содержимым и ряд кнопок — а ему положено стоять.
class FcDialogBody extends StatelessWidget {
  const FcDialogBody({super.key, required this.child, this.actions = const [], this.insets = FcDialogInsets.all});

  /// Содержимое окна — всё, что между полосой заголовка и рядом кнопок.
  final Widget child;

  /// Кнопки окна слева направо, подтверждающая — последняя.
  ///
  /// Пусто — ряда нет вовсе, и места он не занимает: окно без кнопок не
  /// исключение, а случай (палитра команд такова).
  final List<Widget> actions;

  /// Чем содержимое отбито от краёв окна.
  final FcDialogInsets insets;

  @override
  Widget build(BuildContext context) {
    final metrics = FcTheme.of(context).metrics;
    // Высота задана — её надо заполнить; не задана — окно облегает содержимое.
    // Сведение идёт сверху, от рамы: изнутри его не добыть ([FcDialogSizing]).
    final stretches = FcDialogSizing.of(context);
    final side = insets == FcDialogInsets.all ? metrics.dialogHorizontalPadding : 0.0;

    return Column(
      mainAxisSize: stretches ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          fit: stretches ? FlexFit.tight : FlexFit.loose,
          child: Padding(
            padding: EdgeInsets.only(
              left: side,
              right: side,
              // Сверху больше остальных: содержимое отходит от полосы заголовка.
              top: metrics.dialogContentTopPadding,
              bottom: metrics.dialogPadding,
            ),
            // Растянутому окну прокрутка не нужна и вредна: высота у него есть,
            // и распорядиться ею должно содержимое — у тянущихся окон внутри
            // свой список со своим листанием. Облегающему она страхует от
            // переполнения: окно правки атрибутов у файла с десятком
            // расширенных иначе молча вылезало за раму.
            child: stretches ? child : SingleChildScrollView(child: child),
          ),
        ),
        if (actions.isNotEmpty) FcDialogActions(actions: actions),
      ],
    );
  }
}

/// Чем содержимое окна отбито от его краёв.
///
/// Перечислением, а не флагом: боковых полей может не быть по двум разным
/// причинам, и завтра появится третья.
enum FcDialogInsets {
  /// Поля со всех сторон — так стоит содержимое обычного окна.
  all,

  /// Только сверху и снизу; боковые ставит содержимое само.
  ///
  /// Нужно двоим. **Форме** — изнутри, иначе строка `bleed` не смогла бы выйти
  /// за них к краям окна (`FcForm.horizontalPadding`). **Списку с курсором** —
  /// затем, что его строка выбора обязана доходить до краёв: отбитая полями,
  /// она читается не как «эта строка», а как «эта плитка».
  vertical,
}

/// Ряд кнопок внизу окна: отступы и сами кнопки.
///
/// Общий для **всех** окон, и это не удобство, а необходимость: кнопка
/// (`FcButton`) — это `Container` с `alignment`, а такой контейнер под
/// ограниченной по ширине разметкой растягивается во всю её ширину. Ряд
/// с `mainAxisSize: min` даёт кнопкам неограниченную ширину, и каждая
/// получается по своей подписи.
///
/// Правило одно на все окна: **кнопки — по размеру подписи, одной строкой,
/// прижатой вправо** (`HorizontalLayout horizontalAlign="right"` в референсе).
/// Даже там, где кнопка одна.
class FcDialogActions extends StatelessWidget {
  const FcDialogActions({super.key, required this.actions});

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: metrics.dialogHorizontalPadding, vertical: metrics.dialogPadding),
          // Ширина окна задана содержимым и от кнопок не зависит, поэтому пять
          // кнопок (вопрос о занятом имени) в узкое окно могут не помещаться.
          // Тогда `FittedBox` соразмерно уменьшает весь ряд — строка остаётся
          // одной, без переноса и без полосы переполнения.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < actions.length; i++) ...[if (i > 0) SizedBox(width: metrics.dialogGap), actions[i]],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Задан ли окну размер — то есть обязано ли содержимое заполнить высоту.
///
/// **Сведение идёт сверху, потому что снизу его не добыть.** Узнать доставшуюся
/// высоту изнутри можно только `LayoutBuilder`, а он отвечает нулём на вопрос о
/// собственной ширине — тот самый, который рама задаёт каждому окну
/// (`IntrinsicWidth`). Окно, поставившее его у себя внутри, схлопнулось бы до
/// наименьшей ширины темы. Эту грабли проект уже знает — по ней же считает
/// высоту списка палитра команд (`command_palette.dart`).
///
/// Кто ставит: рама окна (`DialogFrame`), и только она — размер окна её дело
/// (`docs/spec/dialog-body.md`).
class FcDialogSizing extends InheritedWidget {
  const FcDialogSizing({super.key, required this.stretches, required super.child});

  /// Высота окна задана: содержимое получит её целиком и обязано заполнить.
  ///
  /// Ложь — окно облегает содержимое, как облегало всегда: высоту назначает
  /// само содержимое, а лишней у него нет.
  final bool stretches;

  /// Тянется ли окно, в котором стоит этот виджет.
  ///
  /// Вне окна — ложь: содержимое, показанное само по себе (в проверках, в
  /// панели), высоты ниоткуда не получает.
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FcDialogSizing>()?.stretches ?? false;

  @override
  bool updateShouldNotify(FcDialogSizing oldWidget) => oldWidget.stretches != stretches;
}
