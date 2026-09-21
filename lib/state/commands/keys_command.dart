import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

/// Настройка клавиш: разделы по контексту, правка нажатием
/// (`docs/spec/key-bindings.md`).
///
/// Реестр — способом его спросить, а не самим реестром: команда живёт внутри
/// него же, и к моменту её создания его ещё нет. Тот же приём, что у справки и
/// палитры.
class KeysCommand extends AppCommand {
  KeysCommand({required CommandRegistry Function() registry}) : _registry = registry;

  final CommandRegistry Function() _registry;

  static const String commandId = 'app.keys';

  @override
  String get id => commandId;

  @override
  String get label => tr('Keyboard');

  @override
  String get description => tr('Set your own key for any command');

  /// Ищут это окно словом «клавиша», а не словом «клавиатура».
  @override
  Set<String> get keywords => const {'keys', 'shortcuts', 'bindings', 'rebind'};

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute(CommandContext context) async {
    final app = context.app;
    final view = app.view;
    late final String dialogId;
    void close() => view.closeDialog(dialogId);

    dialogId = view.showDialog(
      DialogSpec(
        // Английским: окно живёт долго, и заголовок переводит рама — на том
        // языке, который выбран **сейчас**.
        title: 'Keymap',
        id: commandId,
        resizable: true,
        takesFocus: true,
        ownWidth: true,
        // Та же форма, что и у настроек: она принимает произвольные разделы, и
        // второй такой писать незачем (`docs/spec/key-bindings.md`, §8).
        content: FcSettingsForm(
          pages: _pages(app),
          onClose: close,
          searchHint: 'Search commands',
          // «Вернуть всё» относится к окну целиком, а не к разделу: место ему
          // в подвале оглавления (`docs/spec/key-bindings.md`, §8).
          footer: _ResetAllButton(onPressed: () => _resetAll(app)),
        ),
        onSubmit: close,
        onDismiss: close,
      ),
    );
  }

  /// Вернуть все умолчания — и сказать, что вернули.
  ///
  /// Кнопка стоит в подвале, а меняется от неё список: человек смотрит на
  /// кнопку и правки не видит. Нажатие без ответа неотличимо от промаха.
  void _resetAll(Application app) {
    final count = app.keyOverrides.length;
    if (count == 0) {
      app.toasts.show(app.strings.tr('No keys to reset'));
      return;
    }
    app.setKeyOverrides(const []);
    app.toasts.show(app.strings.plural(count, one: 'Reset {n} key', other: 'Reset {n} keys'));
  }

  /// Разделы: по одному на контекст, пустых нет.
  List<SettingsPage> _pages(Application app) {
    final registry = _registry();
    final rows = _rows(registry);
    return [
      for (final context in KeyContext.values)
        if (rows.where((at) => registry.declaredBindings[at].context == context).toList() case final own
            when own.isNotEmpty)
          SettingsPage(
            title: context.title,
            build: () => SettingsSchema([for (final at in own) _field(app, registry, at)], save: () {}),
          ),
    ];
  }

  SettingsKeys _field(Application app, CommandRegistry registry, int at) {
    final registry0 = registry;
    final declared = registry0.declaredBindings[at];
    final command = registry0.find(declared.commandId);
    final label = command?.label ?? declared.commandId;
    final details = _detailsOf(declared);

    return SettingsField.keys(
      declared.id,
      // Значения привязки — в подписи: `Cmd-2` и `Cmd-3` это одна команда «вид
      // панели», и шесть строк с одним названием различить было бы нечем.
      title: details.isEmpty ? label : '$label: $details',
      description: command?.description ?? '',
      keywords: command?.keywords ?? const {},
      read: () => _keyOf(registry0.bindings[at]),
      defaultKeys: _keyOf(declared),
      reset: () => _reset(app, declared.id),
      edit:
          () => _edit(
            app,
            registry0,
            at,
            command: details.isEmpty ? label : '$label: $details',
            context: declared.context?.title ?? '',
          ),
    );
  }

  /// Чем привязку вызывают; пусто — ничем.
  static String _keyOf(KeyBinding binding) => binding.keys == KeyCombination.none ? '' : binding.keys.toString();

  /// Строки окна: настраиваемые привязки, по одной на каждую.
  ///
  /// Строка **и есть привязка** — дело со своим именем: собирать её из
  /// команды, контекста и значений больше не нужно
  /// (`docs/spec/key-bindings.md`, §3).
  List<int> _rows(CommandRegistry registry) {
    final declared = registry.declaredBindings;
    return [
      for (var at = 0; at < declared.length; at++)
        // Внутренняя привязка не показывается и не переназначается; привязка к
        // команде, которой нет, — тем более: модуль выключили.
        if (declared[at].context != null && registry.find(declared[at].commandId) != null) at,
    ];
  }

  /// Открыть окошко записи поверх окна клавиш и дождаться, пока его закроют.
  Future<void> _edit(
    Application app,
    CommandRegistry registry,
    int at, {
    required String command,
    required String context,
  }) async {
    final view = app.view;
    final closed = Completer<void>();
    late final String dialogId;
    void close() {
      view.closeDialog(dialogId);
      if (!closed.isCompleted) {
        closed.complete();
      }
    }

    final declared = registry.declaredBindings[at];
    dialogId = view.showDialog(
      DialogSpec(
        title: 'Key binding',
        content: ListenableBuilder(
          listenable: registry,
          builder:
              (_, _) => FcKeyRecorder(
                command: command,
                context: context,
                read: () => _keyOf(registry.bindings[at]),
                defaultKeys: _keyOf(declared),
                occupiedBy: (keys) => _occupiedBy(registry, at, keys),
                onAssign: (keys) => _assign(app, registry, at, keys),
                onClear: () => _assign(app, registry, at, ''),
                onReset: () => _reset(app, declared.id),
                onClose: close,
              ),
        ),
        onSubmit: close,
        onDismiss: close,
      ),
    );
    return closed.future;
  }

  /// Кто держит эту комбинацию **в том же контексте**; null — никто.
  String? _occupiedBy(CommandRegistry registry, int at, String keys) {
    final combination = KeyCombination.tryParse(keys);
    if (combination == null) {
      return null;
    }
    final probe = registry.declaredBindings[at].withKeys(combination);
    for (var other = 0; other < registry.bindings.length; other++) {
      if (other == at || !registry.bindings[other].conflictsWith(probe)) {
        continue;
      }
      final holder = registry.bindings[other];
      return registry.find(holder.commandId)?.label ?? holder.commandId;
    }
    return null;
  }

  /// Назначить привязке клавишу — и отнять её у того, кто держал.
  void _assign(Application app, CommandRegistry registry, int at, String keys) {
    final overrides = [...app.keyOverrides];
    final declared = registry.declaredBindings;

    if (keys.isNotEmpty) {
      final probe = declared[at].withKeys(KeyCombination.parse(keys));
      for (var other = 0; other < registry.bindings.length; other++) {
        if (other != at && registry.bindings[other].conflictsWith(probe)) {
          _put(overrides, declared[other], '');
        }
      }
    }

    _put(overrides, declared[at], keys);
    app.setKeyOverrides(overrides);
  }

  /// Вернуть умолчание: забыть запись об этой привязке.
  void _reset(Application app, String binding) {
    app.setKeyOverrides([
      for (final override in app.keyOverrides)
        if (override.binding != binding) override,
    ]);
  }

  /// Записать переназначение, заменив прежнее той же привязки.
  static void _put(List<KeyOverride> overrides, KeyBinding declared, String keys) {
    overrides
      ..removeWhere((item) => item.binding == declared.id)
      // Умолчание записью не считается: вернуть его — значит забыть запись.
      ..addAll(keys == _keyOf(declared) ? const [] : [KeyOverride(binding: declared.id, key: keys)]);
  }

  /// Чем эта привязка отличается от соседних у той же команды.
  static String _detailsOf(KeyBinding binding) =>
      binding.parameters.isEmpty ? '' : binding.parameters.values.map((value) => '$value').join(', ');
}

/// Кнопка «вернуть все клавиши» — со своей подписью из словаря.
///
/// Своим виджетом, потому что подпись переводится, а переводчик живёт в дереве:
/// команда строит окно раньше, чем это дерево появится.
class _ResetAllButton extends StatelessWidget {
  const _ResetAllButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FcButton(label: context.strings.tr('Reset all keys'), onPressed: onPressed);
}
