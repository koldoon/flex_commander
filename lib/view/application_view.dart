import 'package:flutter/material.dart';

import 'background/background_bar.dart';
import 'dialogs/command_dialog_layer.dart';
import 'dialogs/credentials_layer.dart';
import 'keyboard_handler.dart';
import 'function_bar/function_bar.dart';
import 'toast_layer.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';

/// Корневой макет окна: экран и ряд функциональных кнопок под ним.
///
/// Что именно показано выше кнопок, ядро не решает: наверху стопки экранов
/// может стоять и модуль панелей, и просмотрщик, и что угодно ещё. Ряд кнопок
/// остаётся на месте всегда — он показывает команды того экрана, который
/// видно.
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
            child: ColoredBox(
              // Фон окна ровный: градиента в референсе нет.
              color: theme.colors.windowBackground,
              child: Column(
                children: [
                  SizedBox(height: metrics.windowTopPadding),
                  Expanded(
                    child: ListenableBuilder(
                      listenable: app.screens,
                      // Пусто — значит показывать нечем: модуль панелей
                      // отключён. Приложение при этом работает, и ряд кнопок
                      // на месте.
                      builder: (context, _) {
                        final screen = app.screens.active;
                        if (screen == null) {
                          return const SizedBox.expand();
                        }
                        return screen.build(context);
                      },
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
