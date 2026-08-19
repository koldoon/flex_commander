import 'package:fc_api/fc_api.dart';
import 'package:flutter/widgets.dart';

/// Виды содержимого панели — реализация [PanelViewports].
///
/// Своих видов у ядра нет ни одного: таблицу файлов приносит модуль панелей,
/// как и всё остальное. Штатный вид — тот, что объявлен под именем
/// [PanelViewports.files]; он же подставляется, когда про вид ничего не
/// известно: модуль, который его объявил, могли отключить, а панель показать
/// что-то обязана.
class PanelViewportRegistry implements PanelViewports {
  PanelViewportRegistry();

  final Map<String, PanelViewportBuilder> _builders = {};

  /// Известные виды содержимого.
  Iterable<String> get kinds => _builders.keys;

  @override
  void register(String kind, PanelViewportBuilder builder) => _builders[kind] = builder;

  /// Нет ни вида, ни штатного — рисовать нечем: модуль панелей отключён.
  /// Пустое место честнее исключения: приложение при этом работает.
  @override
  PanelViewportBuilder builderFor(String kind) =>
      _builders[kind] ?? _builders[PanelViewports.files] ?? (context, panel) => const SizedBox.shrink();
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
