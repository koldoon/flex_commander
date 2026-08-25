import 'package:flutter/widgets.dart';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';

import 'split_view.dart';

/// Две файловые панели с подвижным разделителем — экран, с которого начинается
/// работа.
///
/// Такой же экран, как просмотрщик или редактор: ядро показывает то, что лежит
/// сверху стопки, и о панелях не знает ничего. Отсюда и возможность поставить
/// рядом свой вид над файлами — дерево, три панели, список результатов, — не
/// трогая ядро.
///
/// Фокус себе не берёт: какая панель активна, знает приложение, а нажатия
/// разбирает общий обработчик клавиатуры.
class FilesScreen implements Screen {
  const FilesScreen();

  @override
  String get id => Screens.files;

  /// Фокус панелям не нужен: какая из них активна, знает приложение, а
  /// нажатия разбирает общий обработчик клавиатуры.
  @override
  bool get takesFocus => false;

  /// Закрывать нечего: своего состояния у экрана нет вовсе — он рисует панели,
  /// а живут они в приложении.
  @override
  void close() {}

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);

    return SplitView(
      ratio: app.splitRatio,
      onRatioChanged: app.setSplitRatio,
      // По идентификатору, а не по классу: команда живёт в модуле навигации,
      // и приложение обязано собираться без него — просто разделитель тогда
      // не центруется.
      onCenter: () => app.commands.run(centerSplitCommand),
      left: _place(context, app, app.left),
      right: _place(context, app, app.right),
    );
  }

  /// Рисует то, что стоит в области, — через реестр видов, а не напрямую.
  ///
  /// Пустое место, если вида нет: модуль, объявивший его, могли отключить, а
  /// область показать что-то обязана.
  Widget _place(BuildContext context, Application app, Panel panel) {
    final build = app.views.builderFor(panel);
    return build == null ? const SizedBox.shrink() : build(context, panel);
  }

  /// Действие «разделитель посередине» — если модуль навигации установлен.
  static const String centerSplitCommand = 'app.split.center';
}
