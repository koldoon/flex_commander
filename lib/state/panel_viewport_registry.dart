import 'package:fc_api/fc_api.dart';
import 'package:flutter/widgets.dart';

/// Виды содержимого панели — реализация [PanelViewports].
///
/// Ядро знает ровно один вид: таблицу файлов. Она же и подставляется, когда
/// про вид ничего не известно, — модуль, который его объявил, могли отключить,
/// а панель показать что-то обязана.
class PanelViewportRegistry implements PanelViewports {
  PanelViewportRegistry({required PanelViewportBuilder files}) {
    _builders[PanelViewports.files] = files;
  }

  final Map<String, PanelViewportBuilder> _builders = {};

  /// Известные виды содержимого.
  Iterable<String> get kinds => _builders.keys;

  @override
  void register(String kind, PanelViewportBuilder builder) => _builders[kind] = builder;

  @override
  PanelViewportBuilder builderFor(String kind) => _builders[kind] ?? _builders[PanelViewports.files]!;
}

/// Ни одного вида содержимого.
///
/// Приложению без интерфейса — тесту состояния, сценарию — рисовать нечем и
/// незачем: панель у них есть, а экрана нет.
class NoPanelViewports implements PanelViewports {
  const NoPanelViewports();

  @override
  void register(String kind, PanelViewportBuilder builder) {}

  @override
  PanelViewportBuilder builderFor(String kind) => (context, panel) => const SizedBox.shrink();
}
