import 'package:fc_api/fc_api.dart';
import 'package:flutter/material.dart';

import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'history_arrows.dart';
import 'panels_settings.dart';
import 'panel_status_bar.dart';

/// Панель целиком: «плашка» пути, таблица файлов и строка состояния.
///
/// Рамку и плашку рисует общий [FcPanelFrame] из API — тот же, которым
/// пользуется просмотрщик: место в окне у них одно и то же, и выглядеть они
/// обязаны одинаково.
///
/// О том, левая она или правая, панель знает только ради внешней рамки; всё
/// остальное у обеих одинаково, а какая из них активна, решает приложение.
///
/// Сторону панель выводит сама, а не получает параметром: вид её строит реестр,
/// а он передаёт только состояние — про место в окне ему знать неоткуда.
class PanelView extends StatefulWidget {
  const PanelView({super.key, required this.panel, required this.settings});

  final Session panel;

  /// Настройки видов: полосе состояния нужно знать, сколько ей строчек
  /// (`docs/spec/panel-status-lines.md`).
  final PanelsSettings Function() settings;

  @override
  State<PanelView> createState() => _PanelViewState();
}

/// Со своим состоянием ради одного вопроса: занимает ли нынешний вид раму
/// целиком.
///
/// Ответ меняется вместе с видом и с источником, то есть по сообщению панели, —
/// а подписаться на него шире нельзя: рама, заголовок и строка состояния тогда
/// пересобирались бы на каждое движение курсора. Поэтому подписка узкая:
/// слушаем всё, а перерисовываемся, только когда изменился **ответ**
/// (`docs/spec/panel-redraw.md`).
///
/// Прежде это держалось на том, что область пересказывала чужие уведомления
/// своими, и шелл пересобирал панель целиком. Пересказ убрали — и вид сетки
/// значков перестал доезжать до рамы: содержимое больше не уходило под плашку
/// (поймано эталонным снимком).
class _PanelViewState extends State<PanelView> {
  bool _fills = false;

  @override
  void initState() {
    super.initState();
    widget.panel.addListener(_onPanelChanged);
  }

  @override
  void didUpdateWidget(PanelView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.panel, widget.panel)) {
      oldWidget.panel.removeListener(_onPanelChanged);
      widget.panel.addListener(_onPanelChanged);
    }
  }

  @override
  void dispose() {
    widget.panel.removeListener(_onPanelChanged);
    super.dispose();
  }

  void _onPanelChanged() {
    final fills = _fillsFrame(AppScope.read(context), widget.panel);
    if (fills != _fills) {
      setState(() => _fills = fills);
    }
  }

  @override
  Widget build(BuildContext context) {
    final panel = widget.panel;
    final app = AppScope.read(context);
    // Ответ спрашивается и здесь: первую сборку сообщение панели не опередит,
    // а вид она могла сменить ещё до того, как её начали слушать.
    _fills = _fillsFrame(app, panel);
    // Край берётся у **места**, а не у сессии: одна и та же сессия бывает
    // показана в обеих панелях (`docs/spec/panel-sessions.md`, §7), и по ней
    // левая от правой не отличается.
    final at = ViewportScope.maybeOf(context);
    final outerEdge = switch (at) {
      ViewportPosition.left => PanelOuterEdge.left,
      ViewportPosition.right => PanelOuterEdge.right,
      _ => null,
    };

    return PanelScope(
      panel: panel,
      child: GestureDetector(
        // Клик в любом месте панели делает её активной — поведение референса.
        // Активной становится **эта** панель: щёлкнули по месту, а не по
        // сессии, и показанная в обеих сторонах не должна уводить ввод туда,
        // где он был.
        behavior: HitTestBehavior.translucent,
        onTapDown: (_) => at == null ? app.activate(panel) : app.view.setFocus(at),
        child: FcPanelFrame(
          outerEdge: outerEdge,
          // Раму целиком занимает тот вид, который об этом сказал: у сетки
          // значков содержимое уезжает под плашку, а у списка — нет, там
          // первая строка обязана быть видна.
          fillsFrame: _fills,
          header: ListenableBuilder(
            // И на область тоже: ввод уходит и туда, где панели нет вовсе, —
            // в быстрый просмотр напротив, — а плашка обязана это показать.
            // И на само приложение: заголовок выбирают в настройках, и смена
            // обязана дойти до обеих панелей сразу.
            listenable: Listenable.merge([panel, app.view, app]),
            builder:
                (context, _) => FcPathPlate(
                  path: _headerTextOf(panel),
                  // Чем набрать адрес, решает объявивший заголовок модуль;
                  // никто не объявил или имя чужое — путь строкой, как было
                  // всегда (`docs/spec/panel-header.md`, §6).
                  content: switch (app.panelHeaders.byId(app.panelHeader)) {
                    final header? =>
                      (context, width, style) => header.build(
                        context,
                        PanelHeaderView(panel: panel, text: _headerTextOf(panel), width: width, style: style),
                      ),
                    null => null,
                  },
                  // «Назад» и «вперёд» — только у панели с файлами: у
                  // просмотрщика в этой же плашке истории нет
                  // (`docs/spec/session-history.md`, §9).
                  leading: HistoryArrows(panel: panel),
                  leadingWidth: HistoryArrows.widthOf(FcTheme.of(context)),
                  // Не `panel.active`: та говорит, какая **сессия** —
                  // источник операции, и остаётся собой, когда ввод ушёл в
                  // наложение напротив, а показана она бывает сразу в обеих
                  // панелях. Плашка говорит другое: где сейчас клавиши.
                  active: takesKeysHere(context, panel),
                ),
          ),
          footer: PanelStatusBar(panel: panel, settings: widget.settings),
          // Не таблица файлов, а то, чем рисуется вид содержимого панели:
          // результаты поиска и просмотрщики — такие же жильцы панели, как и
          // файлы. Каталог же человек показывает как хочет — своим видом
          // (`docs/spec/panel-views.md`, §3).
          // Слушает панель: вид выбирает человек (`Cmd-1`…`Cmd-3`), а
          // содержимое — источник, и меняются оба на ходу. Без подписки
          // содержимое оставалось прежним до первой чужой перерисовки — живьём
          // вид не менялся, пока не нажмёшь `Tab`.
          child: ListenableBuilder(listenable: panel, builder: (context, _) => _content(context, app, panel)),
        ),
      ),
    );
  }
}

/// Занимает ли нынешний вид раму целиком.
///
/// Спрашивается у вида, а не решается здесь: панель не знает, как устроено то,
/// что в ней показано. Источник со своим видом содержимого (находки,
/// просмотрщик) раму не заполняет — у них своя рама и свои правила.
bool _fillsFrame(Application app, Session panel) {
  if (panel.source.contentKind != SourceInfo.files) {
    return false;
  }
  return app.panelViews.byId(panel.view)?.fillsFrame ?? false;
}

/// Что показывает плашка: заголовок, выставленный командой, иначе путь.
///
/// Решает это панель, а не заголовок: `headerText` главнее пути, и повторять
/// это правило в каждом заголовке значит однажды повторить его неверно
/// (`docs/spec/panel-header.md`, §3).
String _headerTextOf(Session panel) => panel.headerText ?? (panel.currentPath.isEmpty ? '/' : panel.currentPath);

/// Чем рисовать то, что в панели сейчас.
///
/// Источник со своим видом содержимого главнее выбора человека: список находок
/// останется списком находок, чем бы его ни просили рисовать. Каталог рисуется
/// выбранным видом, а незнакомый вид — таблицей: модуль, объявивший вид, могли
/// выключить, а показать каталог панель обязана.
Widget _content(BuildContext context, Application app, Session panel) {
  if (panel.source.contentKind != SourceInfo.files) {
    return app.viewports.builderFor(panel.source.contentKind)(context, panel);
  }
  final view = app.panelViews.byId(panel.view);
  return view != null ? view.build(context, panel) : app.viewports.builderFor(SourceInfo.files)(context, panel);
}
