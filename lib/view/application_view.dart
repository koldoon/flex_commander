import 'package:flutter/material.dart';

import '../state/app_scope.dart';
import 'background/background_bar.dart';
import 'common/split_view.dart';
import 'dialogs/command_dialog_layer.dart';
import 'dialogs/credentials_layer.dart';
import 'keyboard_handler.dart';
import 'function_bar/function_bar.dart';
import 'panel/panel_view.dart';
import 'toast_layer.dart';
import 'package:fc_api/fc_api.dart';

/// Корневой макет окна: две панели и ряд функциональных кнопок под ними.
class ApplicationView extends StatelessWidget {
  const ApplicationView({super.key});

  /// Действие «разделитель посередине» — если модуль навигации установлен.
  ///
  /// Строкой, а не классом: модуль может быть отключён, и тянуть ради этой
  /// кнопки зависимость на него ядро не должно.
  static const String _centerSplitCommand = 'app.split.center';

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;
    final app = AppScope.of(context);

    return Scaffold(
      body: Stack(
        children: [
          KeyboardHandler(
            app: app,
            child: ColoredBox(
              // Фон окна ровный: градиента в референсе нет.
              color: theme.colors.windowBackground,
              child: Column(
                children: [
                  SizedBox(height: metrics.windowTopPadding),
                  Expanded(
                    child: SplitView(
                      ratio: app.splitRatio,
                      onRatioChanged: app.setSplitRatio,
                      // По идентификатору, а не по классу: команда живёт в
                      // модуле навигации, и приложение обязано собираться без
                      // него — просто разделитель тогда не центруется.
                      onCenter: () => app.commands.run(_centerSplitCommand),
                      left: PanelView(panel: app.left, outerEdge: PanelOuterEdge.left),
                      right: PanelView(panel: app.right, outerEdge: PanelOuterEdge.right),
                    ),
                  ),
                  // Фоновые работы — между панелями и рядом кнопок: их видно,
                  // но место они занимают, только когда есть.
                  BackgroundBar(tasks: app.background),
                  SizedBox(height: metrics.functionBarGap),
                  const FunctionBar(),
                  SizedBox(height: metrics.windowBottomPadding),
                ],
              ),
            ),
          ),
          // Сообщения — над панелями, но под окнами команд: окно важнее, и
          // закрывать его строкой о том, что уже случилось, незачем.
          ToastLayer(toasts: app.toasts),
          // Окна команд рисуются поверх и **вне** обработчика клавиатуры:
          // иначе они не смогли бы принять фокус — он не пускает его внутрь.
          CommandDialogLayer(app: app),
          // Вопрос о пароле — там же и по той же причине. Задаёт его не
          // команда, а тот, кто наткнулся на защищённое.
          CredentialsLayer(credentials: app.credentials),
        ],
      ),
    );
  }
}
