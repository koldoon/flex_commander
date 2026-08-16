import 'package:flutter/material.dart';

import '../state/app_scope.dart';
import 'common/split_view.dart';
import 'dialogs/command_dialog_layer.dart';
import 'keyboard_handler.dart';
import 'function_bar/function_bar.dart';
import 'panel/panel_view.dart';
import 'theme/app_theme.dart';

/// Корневой макет окна: две панели и ряд функциональных кнопок под ними.
class ApplicationView extends StatelessWidget {
  const ApplicationView({super.key});

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
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [theme.colors.windowBackgroundTop, theme.colors.windowBackgroundBottom],
                ),
              ),
              padding: EdgeInsets.all(metrics.windowPadding),
              child: Column(
                children: [
                  Expanded(
                    child: SplitView(
                      ratio: app.splitRatio,
                      onRatioChanged: app.setSplitRatio,
                      left: PanelView(panel: app.left),
                      right: PanelView(panel: app.right),
                    ),
                  ),
                  SizedBox(height: metrics.windowPadding),
                  const FunctionBar(),
                ],
              ),
            ),
          ),
          // Окна команд рисуются поверх и **вне** обработчика клавиатуры:
          // иначе они не смогли бы принять фокус — он не пускает его внутрь.
          CommandDialogLayer(app: app),
        ],
      ),
    );
  }
}
