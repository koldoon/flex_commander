import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'theme_editor_pages.dart';
import 'theme_overlay.dart';

/// Смена темы — командой модуля темы, а не службой оформления: имя выбранной
/// темы сохраняет она (`docs/spec/theme-editor.md`, §13).
///
/// Именем, а не классом: модуль темы редактору чужой, и выключить его должно
/// быть можно — так же его зовёт оболочка у поля «Theme».
const String _switchThemeCommand = 'app.theme.use';
const String _switchThemeParam = 'themeId';

/// Правка оформления: окно, устроенное как сами настройки
/// (`docs/spec/theme-editor.md`).
///
/// Предпросмотра в окне нет: предпросмотр — **само приложение**. Окно отодвигают
/// за заголовок и смотрят, что под ним.
class EditThemeCommand extends AppCommand {
  EditThemeCommand(this.env, this.overlay);

  final FcContext env;

  /// Способом спросить, а не самой накладкой: команда создаётся на каждый
  /// запуск, а накладка — служба, и берётся она тогда, когда нужна.
  final ThemeOverlay Function() overlay;

  static const String commandId = 'theme.edit';

  @override
  String get id => commandId;

  @override
  String get label => tr('Edit theme');

  @override
  String get description => tr('Colors, sizes and fonts of the current theme');

  /// Ищут это окно словом «цвет», а не словом «тема».
  @override
  Set<String> get keywords => const {'colors', 'appearance', 'fonts', 'sizes', 'palette'};

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute(CommandContext context) async {
    final app = context.app;
    final view = app.view;
    final editor = overlay();
    late final String dialogId;
    void close() => view.closeDialog(dialogId);

    dialogId = view.showDialog(
      DialogSpec(
        // Английским: окно живёт долго, и заголовок переводит рама — на том
        // языке, который выбран **сейчас**.
        title: 'Theme',
        id: commandId,
        resizable: true,
        takesFocus: true,
        ownWidth: true,
        // Та же форма, что у настроек и клавиш: она принимает произвольные
        // разделы, и третью такую писать незачем (§3).
        content: FcSettingsForm(
          pages: themeEditorPages(app.theme, editor, save: () {}),
          onClose: close,
          searchHint: 'Search roles',
          footer: (refresh) => _ResetAllButton(onPressed: () => _resetAll(app, editor, refresh)),
        ),
        onSubmit: close,
        onDismiss: close,
      ),
    );
  }

  /// Вернуть всё оформление — и сказать, сколько вернули.
  ///
  /// Кнопка стоит в подвале, а меняется от неё весь экран: нажатие без ответа
  /// неотличимо от промаха.
  void _resetAll(Application app, ThemeOverlay editor, VoidCallback refresh) {
    final count = editor.resetAll();
    if (count == 0) {
      app.toasts.show(app.strings.tr('Nothing to reset'));
      return;
    }
    // Перечитать показанное: правка прошла мимо полей, и в них осталось бы
    // набранное, которого в теме уже нет.
    refresh();
    app.toasts.show(app.strings.plural(count, one: 'Reset {n} role', other: 'Reset {n} roles'));
  }
}

/// Сложить свою тему из того, что на экране.
///
/// Именованные темы: одной накладки на встроенную хватало, пока правка была
/// «подкрутить под себя»; тем, кто держит два оформления и переключается между
/// ними, нужен список (`docs/spec/theme-editor.md`, §6).
class NewThemeCommand extends AppCommand {
  NewThemeCommand(this.env, this.overlay);

  final FcContext env;
  final ThemeOverlay Function() overlay;

  static const String commandId = 'theme.new';

  @override
  String get id => commandId;

  @override
  String get label => tr('New theme');

  @override
  String get description => tr('Save the current look under a name of your own');

  @override
  Set<String> get keywords => const {'appearance', 'colors', 'copy'};

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute(CommandContext context) async {
    final app = context.app;
    final editor = overlay();
    final strings = app.strings;

    await askName(
      app,
      title: strings.tr('New theme'),
      submitLabel: strings.tr('Create'),
      // От названия нынешней: своя тема чаще всего «то же, но моё».
      initial: app.theme.current.title,
      save: (name) {
        if (name.isEmpty) {
          return strings.tr('A theme without a name cannot be chosen');
        }
        if (app.theme.available.any((theme) => theme.title == name)) {
          return strings.tr('There is a theme with this name already');
        }
        final id = editor.create(name);
        app.toasts.show(strings.tr('Theme «{name}» created', args: {'name': name}));
        // Имя выбранной темы сохраняет команда смены темы, а не служба: своя
        // тема обязана пережить перезапуск так же, как встроенная (§13).
        app.commands.run(_switchThemeCommand, CommandInvocation(parameters: {_switchThemeParam: id}));
        return null;
      },
    );
  }
}

/// Убрать свою тему.
///
/// Встроенную убрать нельзя: её объявил модуль, и вернуть её было бы нечем —
/// поэтому на встроенной команда невыполнима, а кнопка приглушена.
class DeleteThemeCommand extends AppCommand {
  DeleteThemeCommand(this.env, this.overlay);

  final FcContext env;
  final ThemeOverlay Function() overlay;

  static const String commandId = 'theme.delete';

  @override
  String get id => commandId;

  @override
  String get label => tr('Delete theme');

  @override
  String get description => tr('Forget a theme of your own');

  @override
  bool isExecutable(CommandContext context) => overlay().overrides.find(context.app.theme.current.id)?.isOwn ?? false;

  @override
  Future<void> execute(CommandContext context) async {
    final app = context.app;
    final editor = overlay();
    final strings = app.strings;
    final theme = app.theme.current;

    await askConfirm(
      app,
      title: strings.tr('Delete theme'),
      message: strings.tr('Delete «{name}»? The theme it was made from stays as it is.', args: {'name': theme.title}),
      confirmLabel: strings.tr('Delete'),
      onConfirm: () {
        if (!editor.remove(theme.id)) {
          return;
        }
        app.toasts.show(strings.tr('Theme «{name}» deleted', args: {'name': theme.title}));
        // Выбор перешёл базе — и это тоже выбор, который надо запомнить.
        app.commands.run(_switchThemeCommand, CommandInvocation(parameters: {_switchThemeParam: app.theme.current.id}));
      },
    );
  }
}

/// Вернуть оформление — без окна.
///
/// Если палитру довели до состояния, в котором окна уже не разглядеть, чинить
/// её тем же окном бессмысленно (`docs/spec/theme-editor.md`, §9).
class ResetThemeCommand extends AppCommand {
  ResetThemeCommand(this.env, this.overlay);

  final FcContext env;
  final ThemeOverlay Function() overlay;

  static const String commandId = 'theme.reset';

  @override
  String get id => commandId;

  @override
  String get label => tr('Reset theme');

  @override
  String get description => tr('Drop every change made to the theme');

  @override
  Set<String> get keywords => const {'colors', 'appearance', 'default'};

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute(CommandContext context) async {
    final app = context.app;
    final count = overlay().resetAll();
    app.toasts.show(
      count == 0
          ? app.strings.tr('Nothing to reset')
          : app.strings.plural(count, one: 'Reset {n} role', other: 'Reset {n} roles'),
    );
  }
}

/// Кладёт накладку при запуске — как `RestoreThemeCommand` возвращает выбранную
/// тему.
///
/// Стартовой командой, а не чтением в `install`: настройки к моменту запуска
/// уже прочитаны, а до него их ещё нет.
class ApplyThemeOverlayCommand extends AppCommand {
  ApplyThemeOverlayCommand(this.env, this.overlay);

  final FcContext env;
  final ThemeOverlay Function() overlay;

  static const String commandId = 'theme.overlay.apply';

  @override
  String get id => commandId;

  @override
  String get label => tr('Apply theme changes');

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute(CommandContext context) async => overlay().start();
}

/// Кнопка «вернуть всё оформление» — со своей подписью из словаря.
///
/// Своим виджетом, потому что подпись переводится, а переводчик живёт в дереве:
/// команда строит окно раньше, чем это дерево появится.
class _ResetAllButton extends StatelessWidget {
  const _ResetAllButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FcButton(label: context.strings.tr('Reset all roles'), onPressed: onPressed);
}
