import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

/// Встроенные наборы клавиш: «как в mc», «как в far», «как в Finder»
/// (`docs/spec/key-presets.md`).
///
/// Модуль не делает ничего, кроме как объявляет три набора: они встают в тот же
/// список, что и наборы, сложенные человеком, — только обновить и удалить их
/// нельзя.
///
/// **Собраны по духу, а не буквально.** Привычка оригинала берётся там, где она
/// работает; занятое системой macOS (`Cmd-W`, `Cmd-Q`, `Cmd-H`) не берётся
/// вовсе — такая клавиша не дойдёт до приложения, и набор молча недосчитался бы
/// дела.
///
/// О чём набор молчит — остаётся умолчание приложения: набор кладётся накладкой
/// (`docs/spec/settings-presets.md`, §4).
class KeyPresets implements FcFrontendModule {
  const KeyPresets();

  static const String moduleId = 'fc.key_presets';

  @override
  String get id => moduleId;

  @override
  String get title => 'Key presets';

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.strings('ru', _russian);

    registry.preset(_preset('mc', _mc));
    registry.preset(_preset('far', _far));
    registry.preset(_preset('Finder', _finder));
  }

  static Preset _preset(String name, Map<String, String> keys) =>
      Preset(name: name, keys: [for (final entry in keys.entries) KeyOverride(binding: entry.key, key: entry.value)]);

  /// Midnight Commander.
  ///
  /// `F1`…`F8`, `Tab`, `Ctrl-O`, `Alt-O`, `+`/`-` и `Ctrl-S` совпадают с
  /// оригиналом и так — их тут нет.
  static const Map<String, String> _mc = {
    'panel.reload': 'Ctrl-R',
    'panel.toggleHidden': 'Alt-.',
    'panel.up': 'Ctrl-PgUp',
    'panel.selection.toggle': 'Ins',
    'terminal.insertName': 'Ctrl-Enter',
  };

  /// Far Manager.
  ///
  /// Адрес панели и выбор вида меняются местами: в far на `Alt-F1`/`Alt-F2`
  /// выбирают диск, а это ближе всего к нашему адресу.
  static const Map<String, String> _far = {
    'file.clipboard.copy': 'Ctrl-Ins',
    'file.clipboard.paste': 'Shift-Ins',
    'file.clipboard.cut': 'Shift-Del',
    'panel.reload': 'Ctrl-R',
    'panel.toggleHidden': 'Ctrl-H',
    'panel.root': r'Ctrl-\',
    'panel.history.choose': 'Alt-F12',
    'panel.openPath.left': 'Alt-F1',
    'panel.openPath.right': 'Alt-F2',
    'panel.view.choose.left': 'Cmd-F1',
    'panel.view.choose.right': 'Cmd-F2',
  };

  /// Finder.
  ///
  /// `Space` занят пометкой, поэтому пометка уезжает на `Ins`: в Finder пробел
  /// это быстрый просмотр, и ради него набор и нужен.
  static const Map<String, String> _finder = {
    'viewer.quickView': 'Space',
    'panel.selection.toggle': 'Ins',
    'panel.toggleHidden': 'Shift-Cmd-.',
    'search.findFiles': 'Cmd-F',
    'panel.sessions.new': 'Cmd-T',
    'terminal.focusLine': 'Cmd-Shift-T',
    'panel.view.icons': 'Cmd-1',
    'panel.view.table': 'Cmd-2',
    'panel.view.columns': 'Cmd-3',
    'file.remove': 'Cmd-Bsp',
    'file.removePermanently': 'Shift-Cmd-Bsp',
    'file.info': 'Cmd-I',
    'file.mkdir': 'Shift-Cmd-N',
    'panel.up': 'Cmd-Up',
    'panel.history.back': 'Cmd-[',
    'panel.history.forward': 'Cmd-]',
    'editor.save': 'Cmd-S',
    'editor.find': 'Cmd-F',
    'editor.findNext': 'Cmd-G',
    'text.find': 'Cmd-F',
    'text.findNext': 'Cmd-G',
  };
}

/// Русские строки наборов.
///
/// Имена самих наборов не переводятся: «mc», «far» и «Finder» — это названия
/// программ, и по-русски они те же.
const Map<String, String> _russian = {'Key presets': 'Наборы клавиш'};
