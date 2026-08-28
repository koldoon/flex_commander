import 'package:fc_api/fc_api.dart';
import 'package:flutter/material.dart';

import 'status_area.dart';
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
      left: _column(context, app, ViewportPosition.left),
      right: _column(context, app, ViewportPosition.right),
    );
  }

  /// Панель и её статусная область — столбец из двух виджетов.
  ///
  /// Область показывает **работу**: только ту, что явно отправили в фон с этой
  /// панели. Место она занимает, лишь когда есть что показать. Про
  /// **содержимое** — объект под курсором, сводку по пометке — говорит строка
  /// внутри самой панели, а не эта область.
  Widget _column(BuildContext context, Application app, ViewportPosition position) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _place(context, app, app.view.contentAt(position))),
        StatusArea(tasks: app.operations, owner: position),
      ],
    );
  }

  /// Поле у ряда кнопок: общее поле окна за вычетом его собственного выступа.
  ///
  /// Ниже нуля не уходит: выступ больше поля означал бы, что ряд вылезает за
  /// край окна, — а это уже не «ближе к краю», а мимо него.
  static double _barSidePadding(FcMetrics metrics) =>
      (metrics.windowSidePadding - metrics.functionBarSideOutset).clamp(0.0, metrics.windowSidePadding);

  /// Что стоит между рабочей областью и рядом кнопок.
  ///
  /// Пусто — просвет ставит шелл: это внешняя рамка окна, и полноэкранный
  /// просмотрщик отбит от кнопок ровно так же, как панели.
  ///
  /// Занято — просветы отмеряет **само содержимое**, с обеих сторон. Иначе к
  /// его собственному воздуху прибавлялась бы ещё и рамка, и текст командной
  /// строки отходил бы от кнопок дальше, чем от панелей.
  Widget _belowWorkArea(BuildContext context, Application app) =>
      _bottomStrip(context, app) ?? SizedBox(height: FcTheme.of(context).metrics.functionBarGap);

  /// Полоса под панелями и над рядом кнопок: командная строка.
  ///
  /// Пустой области нет вовсе — не пустой виджет нулевой высоты, а ничего:
  /// без модуля терминала внизу окна ничего не меняется. Высоту полоса
  /// назначает себе сама: сколько нужно её содержимому, столько и займёт.
  ///
  /// Полноэкранное содержимое её убирает — см. ниже.
  /// null — полосы нет вовсе: ни пустого виджета, ни зазора в никуда.
  Widget? _bottomStrip(BuildContext context, Application app) {
    // Под полноэкранным терминалом её нет: в него и так печатают. Две строки
    // ввода в одну и ту же оболочку — это вопрос «а в какую из них сейчас?»,
    // на который нечего ответить; заодно возвращается строка экрана самому
    // терминалу, ради которого его и разворачивали.
    if (app.view.contentAt(ViewportPosition.fullscreen) != null) {
      return null;
    }

    final content = app.view.contentAt(ViewportPosition.bottom);
    if (content == null) {
      return null;
    }
    // Просветов вокруг полосы шелл не ставит: сколько воздуха ей нужно, знает
    // она сама — у командной строки это `commandLineGap`, сверху и снизу.
    return app.views.builderFor(content)?.call(context, content);
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
                  // Поля по краям — панелям и полосе под ними разом: порознь
                  // они разъехались бы, а полоса стоит ровно под панелями.
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: metrics.windowSidePadding),
                      child: ListenableBuilder(listenable: app.view, builder: (context, _) => _workArea(context, app)),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: metrics.windowSidePadding),
                    child: ListenableBuilder(
                      listenable: app.view,
                      builder: (context, _) => _belowWorkArea(context, app),
                    ),
                  ),
                  // Ряд кнопок стоит ближе к краям: он рисованная клавиатура, и
                  // общая рамка ему ни к чему.
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: _barSidePadding(metrics)),
                    child: const FunctionBar(),
                  ),
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
