import 'package:flutter/widgets.dart';

import 'panel.dart';

/// Чем рисуется содержимое панели.
typedef PanelViewportBuilder = Widget Function(BuildContext context, Panel panel);

/// Виды содержимого панели и то, чем каждый рисуется.
///
/// Панель — это место, а не таблица файлов: в ней может быть список результатов
/// поиска, просмотрщик или дерево каталогов. Ядро знает только про файлы, всё
/// остальное приносят модули.
abstract interface class PanelViewports {
  /// Штатный вид содержимого — таблица файлов.
  static const String files = 'files';

  void register(String kind, PanelViewportBuilder builder);

  /// Чем рисовать этот вид. Для незнакомого вида — таблица файлов: модуль,
  /// объявивший вид, могли отключить, а панель показать что-то обязана.
  PanelViewportBuilder builderFor(String kind);
}
