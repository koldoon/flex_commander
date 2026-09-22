import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

/// Наборы выбора: сложить нынешнее, применить сложенное
/// (`docs/spec/settings-presets.md`).
///
/// **Что входит в набор, решает схема настроек**, а не список полей руками:
/// все поля всех разделов плюс переназначения клавиш. Память — геометрия окна,
/// пути панелей, история команд — не попадает вовсе, потому что её человек не
/// выбирал (`settings-window.md`, §2). Новый модуль попадает в наборы сам,
/// ничего для этого не делая.
class Presets {
  Presets({required Application app, required SettingsCatalog Function() catalog, List<Preset> Function()? embedded})
    : _app = app,
      _catalog = catalog,
      _embedded = embedded ?? _none;

  static List<Preset> _none() => const [];

  final Application _app;

  /// Разделы — способом их спросить: во время создания служб ещё нет.
  final SettingsCatalog Function() _catalog;

  /// Наборы, объявленные приложением (`docs/spec/key-presets.md`).
  final List<Preset> Function() _embedded;

  /// Имя выбранного; пусто — ни один не выбран.
  String get current => _app.preset;

  /// Встроенные впереди своих: они не чьи-то, а приложения.
  List<Preset> get all => [..._embedded(), ..._app.presets];

  Preset? find(String name) => all.where((item) => item.name == name).firstOrNull;

  /// Объявлен ли набор приложением: такой не обновить и не удалить.
  bool isEmbedded(String name) => _embedded().any((item) => item.name == name);

  /// Страницы, которые кладутся в набор: все, кроме самих наборов.
  Iterable<SettingsPage> get _pages => _catalog().pages.where((page) => page.inPreset);

  /// Снимок нынешнего выбора под данным именем.
  Preset capture(String name) {
    final preset = Preset(name: name, keys: _app.keyOverrides);
    for (final page in _pages) {
      for (final field in page.build().fields) {
        final value = field.value;
        if (value != null) {
          preset.put(page.id, field.id, value);
        }
      }
    }
    return preset;
  }

  /// Применить набор **накладкой**: меняется ровно то, о чём он говорит.
  ///
  /// Поле, о котором набор молчит, не трогается — ни к умолчанию, ни к
  /// чему-либо ещё. Иначе набор клавиш «как в mc» сбрасывал бы тему и язык, о
  /// которых он и не думал говорить (`docs/spec/settings-presets.md`, §4).
  void apply(Preset preset) {
    for (final page in _pages) {
      final schema = page.build();
      var touched = false;
      for (final field in schema.fields) {
        final value = preset.valueOf(page.id, field.id);
        if (value == null) {
          continue;
        }
        field.apply(value);
        touched = true;
      }
      if (touched) {
        schema.save();
      }
    }
    _applyKeys(preset.keys);
  }

  /// Клавиши — слиянием по имени привязки: что набор назвал, то и меняется.
  ///
  /// Своё переназначение соседней клавиши остаётся на месте: накладка кладётся
  /// поверх, а не вместо.
  void _applyKeys(List<KeyOverride> keys) {
    if (keys.isEmpty) {
      return;
    }
    final named = {for (final override in keys) override.binding};
    _app.setKeyOverrides([
      for (final override in _app.keyOverrides)
        if (!named.contains(override.binding)) override,
      ...keys,
    ]);
  }

  /// Выбрать набор по имени и применить его; пустое имя — снять выбор.
  ///
  /// Снятие выбора ничего не применяет: «None» это не набор, а его отсутствие,
  /// и возвращать им умолчания значило бы стереть сделанное одним движением
  /// списка.
  void select(String name) {
    final preset = name.isEmpty ? null : find(name);
    if (preset != null) {
      apply(preset);
    }
    _app.setPresets(all, current: preset?.name ?? '');
  }

  /// Сложить нынешнее в новый набор и выбрать его.
  ///
  /// Имя занято — ничего не делается: говорить об этом человеку должно окно,
  /// которое имя и спрашивало.
  bool saveAs(String name) {
    final wanted = name.trim();
    if (wanted.isEmpty || find(wanted) != null) {
      return false;
    }
    _app.setPresets([..._app.presets, capture(wanted)], current: wanted);
    return true;
  }

  /// Переписать выбранный набор тем, что стоит сейчас.
  bool updateCurrent() {
    final name = current;
    // Встроенный не свой: переписать его нечем — он объявлен приложением.
    if (name.isEmpty || isEmbedded(name) || find(name) == null) {
      return false;
    }
    _app.setPresets([
      for (final item in _app.presets)
        if (item.name == name) capture(name) else item,
    ], current: name);
    return true;
  }

  /// Убрать набор; выбранным он быть перестаёт, а настройки остаются как есть.
  bool remove(String name) {
    if (isEmbedded(name) || find(name) == null) {
      return false;
    }
    _app.setPresets([
      for (final item in _app.presets)
        if (item.name != name) item,
    ], current: current == name ? '' : current);
    return true;
  }

  /// Поставить набор, пришедший со стороны, и выбрать его.
  ///
  /// Имя занято — к нему приписывается номер: терять чужой набор или молча
  /// затирать свой одинаково плохо (`docs/spec/settings-presets.md`, §8).
  String add(Preset preset) {
    final name = freeName(preset.name);
    preset.name = name;
    _app.setPresets([..._app.presets, preset], current: name);
    apply(preset);
    return name;
  }

  /// Свободное имя рядом с занятым: «Работа», «Работа 2», «Работа 3».
  String freeName(String wanted) {
    final base = wanted.trim().isEmpty ? 'Preset' : wanted.trim();
    if (find(base) == null) {
      return base;
    }
    for (var next = 2; ; next++) {
      final name = '$base $next';
      if (find(name) == null) {
        return name;
      }
    }
  }
}
