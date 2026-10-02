import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

/// Наборы клавиш: выбрать, сложить свой, убрать, вернуть к началу
/// (`docs/spec/keymaps.md`).
///
/// **Правка у каждого набора своя**, как у тем: что поправили в mc, лежит при
/// mc и вернётся, когда mc выберут снова. Клавиши выбранного набора — это
/// [Application.keyOverrides]; невыбранного — его запись в
/// [Application.keymapEdits] (Default и встроенные) или в самом своём наборе.
class Keymaps {
  Keymaps({required Application app, required List<Keymap> Function() builtIn}) : _app = app, _builtIn = builtIn;

  final Application _app;
  final List<Keymap> Function() _builtIn;

  /// Имя Default: пусто — «ничего не переназначено».
  static const String defaultName = '';

  /// Имя выбранного; пусто — Default. Незнакомое (набор удалили, модуль
  /// выключили) — тоже Default.
  String get current => isKnown(_app.keymap) ? _app.keymap : defaultName;

  List<Keymap> get builtIn => _builtIn();

  List<Keymap> get own => _app.keymaps;

  /// Имена в порядке списка: Default, встроенные, свои.
  List<String> get names => [defaultName, for (final item in builtIn) item.name, for (final item in own) item.name];

  bool isKnown(String name) => names.contains(name);

  bool isBuiltIn(String name) => builtIn.any((item) => item.name == name);

  /// Свой — его можно убрать; Default и встроенные — нет.
  bool isOwn(String name) => own.any((item) => item.name == name);

  /// С чего набор начинается: встроенный — с объявленного модулем, Default и
  /// свой — с умолчаний приложения. К этому возвращает «Reset all keys».
  List<KeyOverride> originOf(String name) => [
    for (final item in builtIn)
      if (item.name == name) ...item.keys,
  ];

  /// Клавиши набора сейчас — у выбранного они действуют.
  List<KeyOverride> keysOf(String name) {
    if (name == current) {
      return _app.keyOverrides;
    }
    if (_app.keymapEdits[name] case final edited?) {
      return edited;
    }
    for (final item in own) {
      if (item.name == name) {
        return item.keys;
      }
    }
    return originOf(name);
  }

  /// Набор как он есть сейчас — для выгрузки.
  Keymap capture(String name) => Keymap(name: name, keys: keysOf(name));

  /// Выбрать набор. Клавиши уходящего запоминаются при нём.
  void select(String name) {
    if (!isKnown(name) || name == current) {
      return;
    }
    final (keymaps, edits) = _leaving();
    final keys = edits.remove(name) ?? keysOf(name);
    _app.setKeymaps(keymap: name, keymaps: keymaps, edits: edits, keys: keys);
  }

  /// Сложить нынешние клавиши в свой набор и выбрать его.
  ///
  /// Имя занято или пусто — ничего не делается: сказать об этом должно окно,
  /// которое имя спрашивало.
  bool saveAs(String name) {
    final wanted = name.trim();
    if (wanted.isEmpty || isKnown(wanted)) {
      return false;
    }
    final keys = [..._app.keyOverrides];
    final (keymaps, edits) = _leaving();
    _app.setKeymaps(keymap: wanted, keymaps: [...keymaps, Keymap(name: wanted, keys: keys)], edits: edits, keys: keys);
    return true;
  }

  /// Убрать свой набор. Был выбран — выбран Default с его клавишами.
  bool remove(String name) {
    if (!isOwn(name)) {
      return false;
    }
    final edits = {..._app.keymapEdits}..remove(name);
    final keymaps = [
      for (final item in own)
        if (item.name != name) item,
    ];
    if (name != current) {
      _app.setKeymaps(keymap: current, keymaps: keymaps, edits: edits, keys: _app.keyOverrides);
      return true;
    }
    final keys = edits.remove(defaultName) ?? const <KeyOverride>[];
    _app.setKeymaps(keymap: defaultName, keymaps: keymaps, edits: edits, keys: keys);
    return true;
  }

  /// Вернуть выбранный набор к его началу ([originOf]).
  void resetCurrent() => _app.setKeyOverrides(originOf(current));

  /// Поставить пришедший набор своим и выбрать его. Имя занято — к нему
  /// приписывается номер: терять чужой или затирать свой одинаково плохо.
  String add(Keymap keymap) {
    final name = freeName(keymap.name);
    final (keymaps, edits) = _leaving();
    _app.setKeymaps(
      keymap: name,
      keymaps: [...keymaps, Keymap(name: name, keys: keymap.keys)],
      edits: edits,
      keys: keymap.keys,
    );
    return name;
  }

  /// Свободное имя рядом с занятым: «Работа», «Работа 2», «Работа 3».
  String freeName(String wanted) {
    final base = wanted.trim().isEmpty ? 'Keymap' : wanted.trim();
    if (!isKnown(base)) {
      return base;
    }
    for (var next = 2; ; next++) {
      final name = '$base $next';
      if (!isKnown(name)) {
        return name;
      }
    }
  }

  /// Свои наборы и правки так, как они станут, когда выбранный перестанет им
  /// быть: его клавиши остаются при нём.
  (List<Keymap>, Map<String, List<KeyOverride>>) _leaving() {
    final name = current;
    final keys = [..._app.keyOverrides];
    final edits = {..._app.keymapEdits};
    final keymaps = [
      for (final item in own)
        if (item.name == name) Keymap(name: name, keys: keys) else item,
    ];
    if (!isOwn(name)) {
      edits[name] = keys;
    }
    return (keymaps, edits);
  }
}
