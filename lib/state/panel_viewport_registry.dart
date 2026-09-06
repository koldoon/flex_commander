import 'package:fc_ui_api/fc_ui_api.dart';
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

/// Виды панели, объявленные модулями.
///
/// Список, а не карта: порядок объявления — это и порядок в окне выбора, а имя
/// в нём заодно и ключ настройки (`docs/spec/panel-views.md`, §6).
class PanelViewRegistry implements PanelViews {
  PanelViewRegistry([List<PanelViewSpec> views = const []]) : _views = List.unmodifiable(views);

  final List<PanelViewSpec> _views;

  @override
  List<PanelViewSpec> get available => _views;

  @override
  PanelViewSpec? byId(String id) {
    for (final view in _views) {
      if (view.id == id) {
        return view;
      }
    }
    return null;
  }
}
