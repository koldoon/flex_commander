import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/foundation.dart';

import 'places_commands.dart';
import 'places_settings.dart';
import 'places_state.dart';
import 'places_view.dart';

/// Боковая полоса избранного: места слева от панелей, щелчок — и панель там
/// (`docs/spec/favorites-sidebar.md`).
///
/// Только экранная половина: места — адреса, переходит по ним панель, и ядру
/// полоса ничего не приносит.
class Places implements FcFrontendModule {
  const Places();

  static const String moduleId = 'fc.places';

  @override
  String get id => moduleId;

  @override
  String get title => 'Sidebar';

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.strings('ru', _russian);

    // Область забирается **сейчас**, пока идёт установка: позже имя раздела
    // уже неизвестно, и настройки уехали бы в чужой.
    final settings = registry.settings;
    PlacesSettings settingsOf() => settings.section(PlacesSettings.new);
    final installer = PlacesInstaller(settings: settingsOf, save: settings.save);

    registry.view<PlacesState>((context, state) => PlacesView(state: state));

    // Полоса ставится стартовой командой: во время объявления нет ни
    // приложения, ни настроек.
    registry.startup((context) => InstallPlacesCommand(installer));

    registry.settingsSchema(() {
      final app = registry.services.resolve<Application>();
      final strings = registry.services.resolve<Strings>();
      return SettingsSchema([
        SettingsField.flag(
          'visible',
          defaultValue: PlacesSettings.visibleByDefault,
          title: strings.tr('Show sidebar'),
          description: strings.tr('Favorite places to the left of the panels'),
          read: () => settingsOf().visible,
          write: (value) => installer.setVisible(app, value),
        ),
        SettingsField.button(
          'restore',
          title: strings.tr('Places'),
          description: strings.tr('Home, Desktop, Documents, Downloads, Applications and the root'),
          label: strings.tr('Restore defaults'),
          run: () async {
            final state = placesOf(app);
            if (state != null) {
              state.restoreDefaults();
            } else {
              settingsOf().restoreDefaults();
              settings.save();
            }
            app.toasts.show(strings.tr('Default places are back'));
          },
        ),
      ], save: settings.save);
    });

    registry.command((context) => TogglePlacesCommand(installer));
    registry.command((context) => FocusPlacesCommand(installer));
    registry.command((context) => AddPlaceCommand(installer));
    registry.command(
      (context) => MovePlacesCursorCommand(id: MovePlacesCursorCommand.upId, label: 'Previous place', step: -1),
    );
    registry.command(
      (context) => MovePlacesCursorCommand(id: MovePlacesCursorCommand.downId, label: 'Next place', step: 1),
    );
    registry.command(
      (context) => MovePlacesCursorCommand(
        id: MovePlacesCursorCommand.firstId,
        label: 'First place',
        step: MovePlacesCursorCommand.toStart,
      ),
    );
    registry.command(
      (context) => MovePlacesCursorCommand(
        id: MovePlacesCursorCommand.lastId,
        label: 'Last place',
        step: MovePlacesCursorCommand.toEnd,
      ),
    );
    registry.command((context) => OpenPlaceCommand(other: false));
    registry.command((context) => OpenPlaceCommand(other: true));
    registry.command((context) => RenamePlaceCommand());
    registry.command((context) => RemovePlaceCommand());
    registry.command((context) => LeavePlacesCommand());

    // Как в Finder: `Ctrl-Cmd-S` — полоса, `Ctrl-Cmd-T` — каталог на неё.
    //
    // Только на macOS. Вне его `Cmd` разбирается как `Ctrl` (`docs/keyboard.md`),
    // и `Ctrl-Cmd-S` сводится к `Ctrl-S` — то есть к `Cmd-S` редактора; так же
    // `Ctrl-Cmd-T` — к `Cmd-T` командной строки. Там клавиш по умолчанию нет:
    // команды есть, клавишу человек назначит сам.
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      registry.binding(
        KeyBinding.anywhere('Ctrl-Cmd-S', TogglePlacesCommand.commandId, context: KeyContext.everywhere),
      );
      registry.binding(KeyBinding('Ctrl-Cmd-T', AddPlaceCommand.commandId, context: KeyContext.panel));
      registry.binding(KeyBinding('Ctrl-Cmd-Left', FocusPlacesCommand.commandId, context: KeyContext.panel));
    } else {
      registry.binding(KeyBinding.unbound(TogglePlacesCommand.commandId, context: KeyContext.everywhere));
      registry.binding(KeyBinding.unbound(AddPlaceCommand.commandId, context: KeyContext.panel));
      registry.binding(KeyBinding.unbound(FocusPlacesCommand.commandId, context: KeyContext.panel));
    }

    // Ходьба, `Enter` и уход — общее поведение, как в панели: не переназначаются.
    for (final (key, command) in const [
      ('Up', MovePlacesCursorCommand.upId),
      ('Down', MovePlacesCursorCommand.downId),
      ('Home', MovePlacesCursorCommand.firstId),
      ('End', MovePlacesCursorCommand.lastId),
      ('PgUp', MovePlacesCursorCommand.firstId),
      ('PgDn', MovePlacesCursorCommand.lastId),
      ('Enter', OpenPlaceCommand.commandId),
      ('Esc', LeavePlacesCommand.commandId),
      ('Tab', LeavePlacesCommand.commandId),
      ('Right', LeavePlacesCommand.commandId),
    ]) {
      registry.binding(KeyBinding.inState<PlacesState>(key, command));
    }
    // Вторая и третья клавиша команды — своим именем: переназначаются они
    // порознь.
    for (final (key, command, id) in const [
      ('Cmd-Enter', OpenPlaceCommand.otherId, null),
      ('F2', RenamePlaceCommand.commandId, null),
      ('Shift-F6', RenamePlaceCommand.commandId, 'places.rename.shiftF6'),
      ('Del', RemovePlaceCommand.commandId, null),
      ('Cmd-Bsp', RemovePlaceCommand.commandId, 'places.remove.cmdBsp'),
      ('F8', RemovePlaceCommand.commandId, 'places.remove.f8'),
    ]) {
      registry.binding(KeyBinding.inState<PlacesState>(key, command, id: id, context: KeyContext.sidebar));
    }
  }
}

const Map<String, String> _russian = {
  'Sidebar': 'Боковая полоса',
  'Favorites': 'Избранное',
  'Install sidebar': 'Показать боковую полосу',
  'Show or hide the favorites sidebar': 'Показать или спрятать боковую полосу избранного',
  'Go to sidebar': 'К боковой полосе',
  'Move the input to the favorites sidebar': 'Перевести ввод в боковую полосу избранного',
  'Add to sidebar': 'Добавить в боковую полосу',
  'Put the current directory on the favorites sidebar': 'Положить текущий каталог на боковую полосу избранного',
  'Previous place': 'Предыдущее место',
  'Next place': 'Следующее место',
  'First place': 'Первое место',
  'Last place': 'Последнее место',
  'Open': 'Открыть',
  'Open in other panel': 'Открыть в соседней панели',
  'Open the place in the active panel': 'Открыть место в активной панели',
  'Open the place in the other panel; the active one stays': 'Открыть место в соседней панели; активная не меняется',
  'Rename': 'Переименовать',
  'Give the place its own name': 'Дать месту своё имя',
  'Remove': 'Убрать',
  'Take the place off the sidebar': 'Убрать место с боковой полосы',
  'Back to panel': 'Вернуться к панелям',
  'Already in sidebar': 'Уже на боковой полосе',
  'Only directories go to the sidebar': 'На боковую полосу кладутся только каталоги',
  'Cannot open {address}': 'Не удалось открыть {address}',
  'Show sidebar': 'Показывать боковую полосу',
  'Favorite places to the left of the panels': 'Избранные места слева от панелей',
  'Places': 'Места',
  'Home, Desktop, Documents, Downloads, Applications and the root':
      'Домашний каталог, «Рабочий стол», «Документы», «Загрузки», «Программы» и корень',
  'Restore defaults': 'Вернуть по умолчанию',
  'Default places are back': 'Места по умолчанию возвращены',
  // Имена знакомых мест — с оговоркой: «Home» и «Root» уже переведены
  // по-другому в других местах приложения.
  'place|Home': 'Домашний каталог',
  'place|Desktop': 'Рабочий стол',
  'place|Documents': 'Документы',
  'place|Downloads': 'Загрузки',
  'place|Applications': 'Программы',
  'place|Root': 'Корень',
};
