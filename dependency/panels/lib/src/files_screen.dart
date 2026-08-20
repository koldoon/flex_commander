import 'package:flutter/widgets.dart';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';

import 'panel_view.dart';
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
      left: PanelView(panel: app.left, outerEdge: PanelOuterEdge.left),
      right: PanelView(panel: app.right, outerEdge: PanelOuterEdge.right),
    );
  }

  /// Действие «разделитель посередине» — если модуль навигации установлен.
  static const String centerSplitCommand = 'app.split.center';
}
