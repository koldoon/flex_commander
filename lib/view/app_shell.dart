import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/material.dart';

import '../state/app_view_controller.dart';

import 'dialogs/command_dialog_layer.dart';
import 'dialogs/credentials_layer.dart';
import 'dialogs/elevation_layer.dart';
import 'dialogs/error_layer.dart';
import 'keyboard_handler.dart';
import 'window_title_bar.dart';
import 'function_bar/function_bar.dart';
import 'toast_layer.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';

/// Шелл: рабочая область, ряд функциональных кнопок под ней и слои поверх.
///
/// Раскладку знает он один — областей шесть, и что в какой лежит, он спрашивает
/// у [ApplicationView]. Чем рисовать содержимое, он не знает вовсе: за этим
/// идёт в реестр видов.
///
/// **Зазоры между областями ставит тоже он один** — одной величиной
/// ([FcMetrics.areaGap]) и по обеим осям. Область рисует содержимое от края до
/// края отведённого места и о соседях не знает: ни «есть ли что-то надо мной»,
/// ни «стою ли я последней над кнопками». Пока зазор принадлежал области,
/// одно и то же расстояние внизу окна выходило разным у каждого виджета, а
/// подгонка под один случай уезжала во все остальные
/// (`spec/layout-gaps.md`).
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
      return _place(context, app, fullscreen, at: ViewportPosition.fullscreen);
    }

    return FcSplitView(
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

  /// Боковая полоса и рабочая область — рядом, через зазор.
  ///
  /// Полоса стоит **по высоте панелей**, над командной строкой, а не рядом с
  /// ней: строка остаётся во всю ширину окна (`spec/favorites-sidebar.md`, §2).
  /// Ширину полоса держит сама — как полоса командной строки держит свою
  /// высоту.
  Widget _panelsRow(BuildContext context, Application app) {
    final work = _MeasuredPanels(view: app.view, child: _workArea(context, app));
    final sidebar = _sidebar(context, app);
    if (sidebar == null) {
      return work;
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        sidebar,
        SizedBox(width: FcTheme.of(context).metrics.areaGap),
        // Край окна слева теперь у полосы: рамка левой панели замыкается.
        Expanded(child: WindowEdges(left: false, child: work)),
      ],
    );
  }

  /// Боковая полоса избранного; null — её нет: ни виджета, ни зазора.
  ///
  /// Под полноэкранным её нет, как нет там и командной строки: просмотрщику и
  /// редактору отдано всё окно, а переходить из них по местам некуда.
  Widget? _sidebar(BuildContext context, Application app) {
    if (app.view.contentAt(ViewportPosition.fullscreen) != null) {
      return null;
    }
    final content = app.view.contentAt(ViewportPosition.sidebar);
    if (content == null) {
      return null;
    }
    final build = app.views.builderFor(content);
    if (build == null) {
      return null;
    }
    return ViewportScope(position: ViewportPosition.sidebar, child: build(context, content));
  }

  /// Панель и всё, что стоит под ней, — столбец областей через зазор.
  ///
  /// Зазор ставит шелл, а не сами области: каждая рисует своё содержимое от
  /// края до края отведённого места и о соседях не знает вовсе. Иначе полосе
  /// пришлось бы вычислять, что над ней и что под ней, — а меняется это на
  /// ходу.
  ///
  /// Статусная область показывает **работу**: только ту, что явно отправили в
  /// фон с этой панели. Место она занимает, лишь когда есть что показать. Про
  /// **содержимое** — объект под курсором, сводку по пометке — говорит строка
  /// внутри самой панели, а не эта область.
  Widget _column(BuildContext context, Application app, ViewportPosition position) {
    final gap = FcTheme.of(context).metrics.areaGap;
    // Слушать работы приходится здесь: есть ли под панелью полоса работ —
    // решает шелл, потому что вместе с полосой появляется и зазор до неё.
    return ListenableBuilder(
      listenable: app.operations,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _place(context, app, app.view.contentAt(position), at: position)),
            for (final area in _below(context, app, position)) ...[SizedBox(height: gap), area],
          ],
        );
      },
    );
  }

  /// Что стоит под панелью: стопка её статусной области, последнее сверху, и
  /// полоса работ под ними.
  ///
  /// Пустых областей в списке нет — ни виджета, ни зазора. Решается это здесь,
  /// а не внутри вида: вид, вернувший пустую коробку нулевой высоты, оставил бы
  /// после себя зазор в никуда.
  ///
  /// **Столбцом, а не наложением** — этим статусная область и отличается от
  /// остальных. Наложение прячет то, что под ним; здесь же каждое сообщение
  /// про своё, и прятать одно другим незачем: идёт работа, а над ней — поиск.
  ///
  /// Последнее — сверху, ближе к панели: свежее оказывается там, куда и так
  /// смотрят.
  List<Widget> _below(BuildContext context, Application app, ViewportPosition panel) {
    final position = panel.status;
    final stack = position == null ? const <ViewportState>[] : app.view.stackAt(position);

    if (position == null) {
      return const [];
    }
    return [for (final state in stack.reversed) _place(context, app, state, at: position)];
  }

  /// Поле у ряда кнопок: общее поле окна за вычетом его собственного выступа.
  ///
  /// Ниже нуля не уходит: выступ больше поля означал бы, что ряд вылезает за
  /// край окна, — а это уже не «ближе к краю», а мимо него.
  static double _barSidePadding(FcMetrics metrics) =>
      (metrics.windowSidePadding - metrics.functionBarSideOutset).clamp(0.0, metrics.windowSidePadding);

  /// Что стоит между рабочей областью и рядом кнопок: зазор, полоса — если она
  /// есть, — и ещё зазор.
  ///
  /// Величина одна на оба случая и выбирать её по наличию полосы не нужно: это
  /// тот же зазор между областями, что и везде. Отсюда же берётся то, ради чего
  /// величины когда-то сводили: полноэкранный терминал кончается там же, где
  /// кончалась бы командная строка, и приглашение при `Ctrl-O` не прыгает
  /// (`spec/terminal.md`, §12).
  Widget _belowWorkArea(BuildContext context, Application app) {
    final gap = FcTheme.of(context).metrics.areaGap;
    final strip = _bottomStrip(context, app);
    if (strip == null) {
      return SizedBox(height: gap);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [SizedBox(height: gap), strip, SizedBox(height: gap)],
    );
  }

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
    // Своего воздуха полоса не отмеряет: зазоры до панелей и до ряда кнопок
    // стоят снаружи, их ставит `_belowWorkArea`.
    return app.views.builderFor(content)?.call(context, content);
  }

  /// Рисует состояние тем, что для него объявлено.
  ///
  /// Пусто — значит показывать нечем: модуль, объявивший вид, отключён.
  /// Приложение при этом работает, и ряд кнопок на месте.
  /// Место кладётся в дерево вместе с содержимым: само оно своего места не
  /// знает, а одна сессия бывает показана сразу в обеих панелях
  /// (`spec/panel-sessions.md`, §7).
  Widget _place(BuildContext context, Application app, ViewportState? state, {required ViewportPosition at}) {
    if (state == null) {
      return const SizedBox.expand();
    }
    final build = app.views.builderFor(state);
    return ViewportScope(position: at, child: build == null ? const SizedBox.expand() : build(context, state));
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
                  // Системной полосы заголовка у окна нет — вместо неё эта: за
                  // неё окно двигают, и в ней стоит светофор macOS.
                  const WindowTitleBar(),
                  SizedBox(height: metrics.windowTopPadding),
                  // Поля по краям — панелям и полосе под ними разом: порознь
                  // они разъехались бы, а полоса стоит ровно под панелями.
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: metrics.windowSidePadding),
                      child: ListenableBuilder(listenable: app.view, builder: (context, _) => _panelsRow(context, app)),
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
          // Вопрос о пароле, согласие на запись от администратора и ошибка,
          // которую никто не поймал, — окна той же стопки, а не слои сбоку:
          // одни правила места, фокуса и закрытия на все
          // (`docs/spec/child-dialogs.md`, §4.5). Сами эти виджеты ничего не
          // рисуют: они кладут окно в стопку, когда есть о чём спросить.
          CredentialsLayer(credentials: app.credentials, view: app.view),
          ElevationLayer(elevation: app.elevation, view: app.view),
          ErrorLayer(errors: app.errors, toasts: app.toasts, view: app.view),

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

/// Рабочая область, которая умеет сказать, где она стоит.
///
/// Окна команд встают над своей панелью, и место это — доля ширины окна. С
/// боковой полосой панели занимают окно не целиком, и долю разделителя уже
/// нельзя считать долей окна. Сколько отняла полоса, видно только по
/// раскладке, — её и спрашивают, **когда окно встаёт**, а не запоминают
/// заранее: ширину полосы тянут мышью, и запомненное устарело бы молча.
class _MeasuredPanels extends StatefulWidget {
  const _MeasuredPanels({required this.view, required this.child});

  final ApplicationView view;
  final Widget child;

  @override
  State<_MeasuredPanels> createState() => _MeasuredPanelsState();
}

class _MeasuredPanelsState extends State<_MeasuredPanels> {
  double _windowWidth = 0;
  double _sidePadding = 0;

  @override
  void initState() {
    super.initState();
    _controller?.measurePanels(_measure);
  }

  @override
  void dispose() {
    _controller?.measurePanels(null);
    super.dispose();
  }

  AppViewController? get _controller => switch (widget.view) {
    final AppViewController controller => controller,
    _ => null,
  };

  /// Доля окна от левого края рабочей области до правого края окна.
  ///
  /// Поле окна в долю не входит: без полосы ответ — всё окно, ровно как
  /// считали до неё, и окна команд не сдвигаются ни на точку.
  DialogArea _measure() {
    final box = context.findRenderObject();
    if (!mounted || box is! RenderBox || !box.hasSize || _windowWidth <= 0) {
      return DialogArea.window;
    }
    final left = box.localToGlobal(Offset.zero).dx - _sidePadding;
    final start = (left / _windowWidth).clamp(0.0, 0.9);
    return start <= 0 ? DialogArea.window : DialogArea(start: start);
  }

  @override
  Widget build(BuildContext context) {
    _windowWidth = MediaQuery.sizeOf(context).width;
    _sidePadding = FcTheme.of(context).metrics.windowSidePadding;
    return widget.child;
  }
}
