import 'package:flutter/material.dart';

import '../../state/app_scope.dart';
import 'package:fc_api/fc_api.dart';
import 'function_button.dart';

/// Ряд функциональных кнопок внизу окна.
///
/// Это нарисованная клавиатура: панель сама спрашивает у реестра, какая команда
/// закреплена за `F1`…`F10`, показывает её название и по нажатию отправляет ту
/// же комбинацию, что пришла бы с настоящей клавиши. Поэтому команды ничего не
/// знают о нижней панели, а кнопка и клавиша не могут разойтись — даже когда
/// привязки станут настраиваемыми.
class FunctionBar extends StatelessWidget {
  const FunctionBar({super.key});

  /// Сколько функциональных клавиш показывать.
  static const int keyCount = 10;

  @override
  Widget build(BuildContext context) {
    final metrics = FcTheme.of(context).metrics;
    final app = AppScope.of(context);

    return SizedBox(
      height: metrics.functionButtonHeight,
      child: ListenableBuilder(
        // Доступность кнопок зависит от состояния активной панели: есть ли
        // объект под курсором, не занята ли панель. А набор команд меняется и
        // сам по себе: модуль может поставить свою команду после запуска.
        listenable: Listenable.merge([app.left, app.right, app.commands]),
        builder:
            (context, _) => Padding(
              // Поле справа: `paddingRight="30"` у раскладки кнопок.
              padding: EdgeInsets.only(right: metrics.functionBarRightPadding),
              child: Row(
                children: [
                  for (var number = 1; number <= keyCount; number++) ...[
                    if (number > 1) SizedBox(width: metrics.functionButtonGap),
                    Expanded(child: _button(context, number)),
                  ],
                ],
              ),
            ),
      ),
    );
  }

  Widget _button(BuildContext context, int number) {
    final registry = AppScope.read(context).commands;
    final keys = KeyCombination('F$number');
    final command = registry.commandFor(keys);

    if (command == null) {
      return FunctionButton(number: number, label: '-', enabled: false);
    }

    return FunctionButton(
      number: number,
      label: command.label,
      enabled: registry.isExecutable(command),
      // Нажатие мышью — это нажатие той же клавиши.
      onPressed: () => registry.dispatch(keys),
    );
  }
}
