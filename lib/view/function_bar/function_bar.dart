import 'package:flutter/material.dart';

import 'package:fc_ui_kit/fc_ui_kit.dart';
import '../modifiers_scope.dart';
import 'function_button.dart';

/// Ряд функциональных кнопок внизу окна.
///
/// Это нарисованная клавиатура: панель сама спрашивает у реестра, какая команда
/// закреплена за `F1`…`F10`, показывает её название и по нажатию отправляет ту
/// же комбинацию, что пришла бы с настоящей клавиши. Поэтому команды ничего не
/// знают о нижней панели, а кнопка и клавиша не могут разойтись — даже когда
/// привязки станут настраиваемыми.
///
/// **Пока зажат модификатор, показывается его слой**: за F-клавишами живут не
/// только «чистые» команды, но и `Shift-F5`, `Shift-F7`, `Shift-F8`, а узнать
/// о них иначе можно только из справки. Клавиши, за которыми в этом слое ничего
/// нет, показываются прочерком: ряд говорит о том, что клавиша сделает **сейчас**,
/// а смешивать слои значило бы врать — «Copy» на `F5`, когда `Shift-F5` пакует
/// архив.
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
        // Область — потому что за одной и той же клавишей при разном
        // содержимом стоят разные команды, и ряд обязан показывать команды
        // того, что сейчас видно.
        // Зажатые модификаторы сюда не входят: на них ряд подписан самим
        // обращением к ModifiersScope — тот перестроит зависимых сам.
        listenable: Listenable.merge([app.left, app.right, app.commands, app.view]),
        builder: (context, _) {
          final layer = _layerOf(context);

          return Padding(
            // Поле справа: `paddingRight="30"` у раскладки кнопок.
            padding: EdgeInsets.only(right: metrics.functionBarRightPadding),
            child: Row(
              children: [
                for (var number = 1; number <= keyCount; number++) ...[
                  if (number > 1) SizedBox(width: metrics.functionButtonGap),
                  Expanded(child: _button(context, layer, number)),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  /// Какой слой показывать: зажатый — или базовый, если зажатому показать
  /// нечего.
  ///
  /// Слой без единой привязки не показывается вовсе: ряд из десяти прочерков
  /// ничего не сообщает, а выглядит как поломка. Стоит появиться первой
  /// привязке — слой показывается целиком, и клавиши без команды в нём честно
  /// пустые: смешивать слои значило бы врать.
  KeyModifiers _layerOf(BuildContext context) {
    final app = AppScope.read(context);
    final registry = app.commands;

    // Пока открыто окно команды, клавиши принадлежат ему: показывать слой
    // модификатора значило бы обещать то, чего сейчас не будет. Заодно ряд не
    // мигает, когда Shift зажимают ради заглавной буквы в поле имени.
    // Окно бывает и своё у команды, и принадлежащее рабочей области: клавиши
    // в обоих случаях принадлежат ему, и обещать слой модификаторов нельзя.
    final noDialogs = app.view.dialogs.isEmpty;
    final held = noDialogs ? ModifiersScope.of(context) : KeyModifiers.none;
    if (held.isEmpty) {
      return held;
    }

    final known = Iterable.generate(keyCount, (index) => held.on('F${index + 1}'));
    return known.any((keys) => registry.commandFor(keys) != null) ? held : KeyModifiers.none;
  }

  Widget _button(BuildContext context, KeyModifiers layer, int number) {
    final app = AppScope.read(context);
    final registry = app.commands;

    final keys = layer.on('F$number');
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
