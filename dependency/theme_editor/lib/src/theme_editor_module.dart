import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import 'theme_editor_commands.dart';
import 'theme_overlay.dart';
import 'theme_overrides.dart';

/// Редактор тем: цвета, размеры и шрифты правятся в самом приложении
/// (`docs/spec/theme-editor.md`).
///
/// Выключен — темы остаются, править их нечем, кнопка из окна настроек исчезает
/// вместе с командой, а сделанные правки целы и ждут в настройках.
class ThemeEditing implements FcFrontendModule {
  const ThemeEditing();

  static const String commandId = 'fc.theme_editor';

  @override
  String get id => commandId;

  @override
  String get title => 'Theme editor';

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.strings('ru', _russian);
    registry.plurals('ru', _plurals);

    final settings = registry.settings;

    // Накладка — служба: её спрашивают и окно, и возврат, и стартовая команда,
    // а состояние у неё одно на приложение — запомненная база темы.
    registry.service<ThemeOverlay>(
      (services) => ThemeOverlay(
        themes: services.resolve<Application>().theme,
        overrides: settings.section(ThemeOverrides.new),
        save: settings.save,
      ),
    );

    ThemeOverlay overlay(FcContext context) => context.resolve<ThemeOverlay>();

    registry.command((context) => EditThemeCommand(context, () => overlay(context)));
    registry.command((context) => NewThemeCommand(context, () => overlay(context)));
    registry.command((context) => DeleteThemeCommand(context, () => overlay(context)));
    registry.command((context) => ExportThemeCommand(context, () => overlay(context)));
    registry.command((context) => ImportThemeCommand(context, () => overlay(context)));
    registry.command((context) => ResetThemeCommand(context, () => overlay(context)));
    // Клавиш редактор не получает: оформление правят раз в жизни. Привязка без
    // клавиши говорит только о том, в каком разделе стоит команда
    // (`docs/spec/key-bindings.md`, §5).
    registry.binding(KeyBinding.unbound(EditThemeCommand.commandId, context: KeyContext.everywhere));
    registry.binding(KeyBinding.unbound(NewThemeCommand.commandId, context: KeyContext.everywhere));
    registry.binding(KeyBinding.unbound(DeleteThemeCommand.commandId, context: KeyContext.everywhere));
    registry.binding(KeyBinding.unbound(ExportThemeCommand.commandId, context: KeyContext.everywhere));
    registry.binding(KeyBinding.unbound(ImportThemeCommand.commandId, context: KeyContext.everywhere));
    registry.binding(KeyBinding.unbound(ResetThemeCommand.commandId, context: KeyContext.everywhere));

    registry.startup((context) => ApplyThemeOverlayCommand(context, () => overlay(context)));
  }
}

/// Русские строки редактора тем.
const Map<String, String> _russian = {
  'Theme editor': 'Редактор тем',
  'Edit theme': 'Править оформление',
  'Colors, sizes and fonts of the current theme': 'Цвета, размеры и шрифты выбранной темы',
  // «Create» и «Delete» переведены другими модулями: словарь на язык один, и
  // второй перевод той же строки — ошибка сборки.
  'New theme': 'Своё оформление',
  'Save the current look under a name of your own': 'Сохранить нынешний вид под своим именем',
  'A theme without a name cannot be chosen': 'Оформление без имени не выбрать',
  'There is a theme with this name already': 'Оформление с таким именем уже есть',
  'Theme «{name}» created': 'Оформление «{name}» сложено',
  'Delete theme': 'Убрать оформление',
  'Forget a theme of your own': 'Забыть своё оформление',
  'Delete «{name}»? The theme it was made from stays as it is.':
      'Убрать «{name}»? Оформление, с которого оно списано, останется как есть.',
  'Theme «{name}» deleted': 'Оформление «{name}» убрано',
  'Export theme': 'Выгрузить оформление',
  'Save the current look to a file': 'Сохранить нынешний вид файлом',
  'Theme «{name}» exported': 'Оформление «{name}» выгружено',
  'Import theme': 'Загрузить оформление',
  'Bring a theme from a file; it joins the list and becomes the chosen one':
      'Взять оформление из файла: оно встанет в список и станет выбранным',
  'Theme «{name}» imported': 'Оформление «{name}» загружено',
  'This is not a theme: the file does not read': 'Это не оформление: файл не читается',
  'Bring a theme from a file': 'Взять оформление из файла',
  'Reset theme': 'Вернуть оформление',
  'Drop every change made to the theme': 'Забыть все правки оформления',
  'Apply theme changes': 'Применить правки оформления',
  'Reset all roles': 'Вернуть всё',
  'Nothing to reset': 'Возвращать нечего',
  'Search roles': 'Поиск роли',
  'Interface font': 'Шрифт интерфейса',
  'Family name; empty means the one the system picks': 'Название семейства; пусто — тот, что выберет система',
  'File list font': 'Шрифт списка файлов',
  'Monospaced, so that sizes and dates stand in columns': 'Моноширинный, чтобы размеры и даты стояли столбцами',
  'File list fallback fonts': 'Запасные шрифты списка',
  'What to set the list in when the font above is not installed': 'Чем набрать список, если шрифта выше в системе нет',
};

/// Множественные формы: ключ — форма `other`, какой её назвали на месте.
const Map<String, PluralForms> _plurals = {
  'Reset {n} roles': (one: 'Вернули {n} роль', few: 'Вернули {n} роли', many: 'Вернули {n} ролей'),
};
