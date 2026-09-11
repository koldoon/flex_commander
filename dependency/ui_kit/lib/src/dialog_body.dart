import 'package:flutter/widgets.dart';

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
