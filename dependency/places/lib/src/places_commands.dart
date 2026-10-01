import 'package:fc_ui_api/fc_ui_api.dart';

import 'places_settings.dart';
import 'places_state.dart';

/// Полоса, если она показана.
PlacesState? placesOf(Application app) => switch (app.view.contentAt(ViewportPosition.sidebar)) {
  final PlacesState state => state,
  _ => null,
};

/// Полоса показана и ввод у неё, а имя не правят: тогда клавиши полосы её.
///
/// Пока правят имя, команды полосы невыполнимы — и нажатие проходит в поле
/// ввода: `Enter` принимает имя, `Esc` отменяет, буквы печатаются.
PlacesState? _focusedPlaces(Application app) {
  final state = placesOf(app);
  if (state == null || state.renaming != null || app.view.activeArea != ViewportPosition.sidebar) {
    return null;
  }
  return state;
}

/// Как полоса появляется и убирается: команды и стартовая — одним путём.
class PlacesInstaller {
  PlacesInstaller({required this.settings, required this.save});

  final PlacesSettings Function() settings;
  final void Function() save;

  void show(Application app) {
    if (placesOf(app) != null) {
      return;
    }
    app.view.setViewportContent(ViewportPosition.sidebar, PlacesState(app: app, settings: settings, save: save));
  }

  void hide(Application app) {
    if (placesOf(app) case final state?) {
      app.view.removeViewportContent(ViewportPosition.sidebar, state);
    }
  }

  /// Показать или спрятать — и запомнить выбор.
  void setVisible(Application app, bool visible) {
    visible ? show(app) : hide(app);
    settings().visible = visible;
    save();
  }
}

/// Ставит полосу при запуске, если её не прятали.
///
/// Без ожиданий: стартовая команда, ждущая чего-нибудь, вешает каждый тест,
/// где собирается приложение.
class InstallPlacesCommand extends AppCommand {
  InstallPlacesCommand(this.installer);

  static const String commandId = 'places.install';

  final PlacesInstaller installer;

  @override
  String get id => commandId;

  @override
  String get label => tr('Install sidebar');

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute(CommandContext context) async {
    if (installer.settings().visible) {
      installer.show(context.app);
    }
  }
}

/// `Ctrl-Cmd-S` — показать или спрятать полосу, как в Finder.
class TogglePlacesCommand extends AppCommand {
  TogglePlacesCommand(this.installer);

  static const String commandId = 'places.toggle';

  final PlacesInstaller installer;

  @override
  String get id => commandId;

  @override
  String get label => tr('Sidebar');

  @override
  String get description => tr('Show or hide the favorites sidebar');

  @override
  Set<String> get keywords => const {'favorites', 'places', 'bookmarks', 'finder'};

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute(CommandContext context) async {
    final app = context.app;
    final visible = placesOf(app) == null;
    if (!visible && app.view.activeArea == ViewportPosition.sidebar) {
      app.view.setFocus(app.view.sourceArea);
    }
    installer.setVisible(app, visible);
  }
}

/// `Ctrl-Cmd-Left` — ввод полосе. Спрятанную заодно показывает: просили
/// выбрать место, а выбирать не из чего.
class FocusPlacesCommand extends AppCommand {
  FocusPlacesCommand(this.installer);

  static const String commandId = 'places.focus';

  final PlacesInstaller installer;

  @override
  String get id => commandId;

  @override
  String get label => tr('Go to sidebar');

  @override
  String get description => tr('Move the input to the favorites sidebar');

  @override
  Set<String> get keywords => const {'favorites', 'places', 'bookmarks'};

  /// Под полноэкранным полосы нет — и ввод отдавать некому.
  @override
  bool isExecutable(CommandContext context) =>
      context.app.view.contentAt(ViewportPosition.fullscreen) == null &&
      context.app.view.activeArea != ViewportPosition.sidebar;

  @override
  Future<void> execute(CommandContext context) async {
    final app = context.app;
    if (placesOf(app) == null) {
      installer.setVisible(app, true);
    }
    app.view.setFocus(ViewportPosition.sidebar);
  }
}

/// `Ctrl-Cmd-T` — текущий каталог активной панели на полосу, в конец.
class AddPlaceCommand extends AppCommand {
  AddPlaceCommand(this.installer);

  static const String commandId = 'places.add';

  final PlacesInstaller installer;

  @override
  String get id => commandId;

  @override
  String get label => tr('Add to sidebar');

  @override
  String get description => tr('Put the current directory on the favorites sidebar');

  @override
  Set<String> get keywords => const {'favorites', 'places', 'bookmark', 'pin'};

  @override
  bool isExecutable(CommandContext context) => context.app.activePanel.currentPath.isNotEmpty;

  @override
  Future<void> execute(CommandContext context) async {
    final app = context.app;
    // Добавили — значит хотят видеть: спрятанная полоса показывается.
    if (placesOf(app) == null) {
      installer.setVisible(app, true);
    }
    placesOf(app)?.add(app.activePanel.currentPath);
  }
}

/// Ход курсора полосы: на шаг, в начало, в конец.
class MovePlacesCursorCommand extends AppCommand {
  MovePlacesCursorCommand({required this.id, required this.label, required this.step});

  static const String upId = 'places.up';
  static const String downId = 'places.down';
  static const String firstId = 'places.first';
  static const String lastId = 'places.last';

  @override
  final String id;

  @override
  final String label;

  /// Шаг курсора; [toStart] и [toEnd] — до края.
  final int step;

  static const int toStart = -1 << 20;
  static const int toEnd = 1 << 20;

  @override
  bool isExecutable(CommandContext context) => _focusedPlaces(context.app) != null;

  @override
  Future<void> execute(CommandContext context) async {
    final state = _focusedPlaces(context.app);
    if (state == null) {
      return;
    }
    state.moveCursor(state.cursor + step);
  }
}

/// `Enter` — в активную панель, `Cmd-Enter` — в соседнюю.
class OpenPlaceCommand extends AppCommand {
  OpenPlaceCommand({required this.other});

  static const String commandId = 'places.open';
  static const String otherId = 'places.openOther';

  final bool other;

  @override
  String get id => other ? otherId : commandId;

  @override
  String get label => other ? tr('Open in other panel') : tr('Open');

  @override
  String get description =>
      other ? tr('Open the place in the other panel; the active one stays') : tr('Open the place in the active panel');

  @override
  bool isExecutable(CommandContext context) {
    final state = _focusedPlaces(context.app);
    return state != null && state.places.isNotEmpty;
  }

  @override
  Future<void> execute(CommandContext context) async {
    final state = _focusedPlaces(context.app);
    if (state == null) {
      return;
    }
    await state.open(state.cursor, other: other);
  }
}

/// `F2` — имя места на месте подписи.
class RenamePlaceCommand extends AppCommand {
  static const String commandId = 'places.rename';

  @override
  String get id => commandId;

  @override
  String get label => tr('Rename');

  @override
  String get description => tr('Give the place its own name');

  @override
  bool isExecutable(CommandContext context) {
    final state = _focusedPlaces(context.app);
    return state != null && state.places.isNotEmpty;
  }

  @override
  Future<void> execute(CommandContext context) async {
    final state = _focusedPlaces(context.app);
    state?.startRename(state.cursor);
  }
}

/// `Del` — убрать место с полосы. Без вопроса, как в Finder.
class RemovePlaceCommand extends AppCommand {
  static const String commandId = 'places.remove';

  @override
  String get id => commandId;

  @override
  String get label => tr('Remove');

  @override
  String get description => tr('Take the place off the sidebar');

  @override
  bool isExecutable(CommandContext context) {
    final state = _focusedPlaces(context.app);
    return state != null && state.places.isNotEmpty;
  }

  @override
  Future<void> execute(CommandContext context) async {
    final state = _focusedPlaces(context.app);
    state?.remove(state.cursor);
  }
}

/// `Esc`, `Tab`, `Right` — ввод обратно панели.
class LeavePlacesCommand extends AppCommand {
  static const String commandId = 'places.leave';

  @override
  String get id => commandId;

  @override
  String get label => tr('Back to panel');

  @override
  bool isExecutable(CommandContext context) => _focusedPlaces(context.app) != null;

  @override
  Future<void> execute(CommandContext context) async {
    final view = context.app.view;
    view.setFocus(view.sourceArea);
  }
}
