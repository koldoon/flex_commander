import 'package:fc_api/fc_api.dart';
import 'package:flutter/material.dart';

import 'background/background_bar.dart';
import 'dialogs/command_dialog_layer.dart';
import 'dialogs/credentials_layer.dart';
import 'dialogs/error_layer.dart';
import 'keyboard_handler.dart';
import 'split_view.dart';
import 'function_bar/function_bar.dart';
import 'toast_layer.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';

/// Шелл: рабочая область, ряд функциональных кнопок под ней и слои поверх.
///
/// Раскладку знает он один — областей шесть, и что в какой лежит, он спрашивает
/// у [ApplicationView]. Чем рисовать содержимое, он не знает вовсе: за этим
/// идёт в реестр видов.
///
/// Что именно показано выше кнопок, ядро не решает: в областях лежат состояния,
/// а чем их рисовать, объявляют модули. Ряд кнопок остаётся на месте всегда —
/// он показывает команды того, что сейчас видно.
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  /// Рабочая область: полноэкранное, если оно есть, иначе две панели.
  ///
  /// Разделитель считается от доли ширины окна, а она принадлежит рабочей
  /// области целиком, — поэтому и разделитель рисует шелл, а не модуль
  /// панелей.
  Widget _workArea(BuildContext context, Application app) {
    final fullscreen = app.view.contentAt(ViewportPosition.fullscreen);
    if (fullscreen != null) {
      return _place(context, app, fullscreen);
    }

    return SplitView(
      ratio: app.splitRatio,
      onRatioChanged: app.setSplitRatio,
      // По идентификатору, а не по классу: команда живёт в модуле навигации,
      // и приложение обязано собираться без него — просто разделитель тогда
      // не центруется.
      onCenter: () => app.commands.run(centerSplitCommand),
      left: _place(context, app, app.view.contentAt(ViewportPosition.left)),
      right: _place(context, app, app.view.contentAt(ViewportPosition.right)),
    );
  }

  /// Рисует состояние тем, что для него объявлено.
  ///
  /// Пусто — значит показывать нечем: модуль, объявивший вид, отключён.
  /// Приложение при этом работает, и ряд кнопок на месте.
  Widget _place(BuildContext context, Application app, ViewportState? state) {
    if (state == null) {
      return const SizedBox.expand();
    }
    final build = app.views.builderFor(state);
    return build == null ? const SizedBox.expand() : build(context, state);
  }

  /// Действие «разделитель посередине» — если модуль навигации установлен.
  static const String centerSplitCommand = 'app.split.center';

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
                    child: ListenableBuilder(listenable: app.view, builder: (context, _) => _workArea(context, app)),
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
          // Окна команд рисуются поверх и **вне** обработчика клавиатуры:
          // иначе они не смогли бы принять фокус — он не пускает его внутрь.
          CommandDialogLayer(app: app),
          // Вопрос о пароле — там же и по той же причине. Задаёт его не
          // команда, а тот, кто наткнулся на защищённое.
          CredentialsLayer(credentials: app.credentials),

          // Ошибка, которую никто не поймал, — поверх окон: пока о ней не
          // сказали, продолжать всё равно нечего.
          ErrorLayer(errors: app.errors, toasts: app.toasts),

          // Сообщения — выше всех, включая окна.
          //
          // Раньше они лежали под окнами: считалось, что окно важнее строчки о
          // том, что уже случилось. Но говорят этой строчкой и сами окна —
          // «Report» в окне ошибки кладёт отчёт в буфер и сообщает об этом, —
          // а под затенением сообщение почти не видно: подтверждение пропадает
          // ровно тогда, когда его ждут. Перекрыть окно оно не может: это
          // полоска у нижнего края, и нажатия она пропускает насквозь
          // (`IgnorePointer`).
          ToastLayer(toasts: app.toasts),
        ],
      ),
    );
  }
}
