import 'package:flutter/widgets.dart';

import '../app/panel.dart';

/// Провайдер, содержимое которого рисуется не таблицей файлов.
///
/// Интерфейс, а не флаг: про флаг можно соврать, про наличие метода нельзя —
/// то же правило, что у [NodeEditor] и остального в провайдерах.
abstract interface class PanelContent {
  /// Вид содержимого: `search`, `viewer`, `image`. Под это имя модуль
  /// регистрирует то, чем оно рисуется.
  String get contentKind;
}

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
