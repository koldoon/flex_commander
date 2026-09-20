import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

/// Настройка клавиш: все привязки списком, назначение нажатием
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
    final registry = _registry();
    final app = context.app;
    final view = app.view;
    late final String dialogId;
    void close() => view.closeDialog(dialogId);

    dialogId = view.showDialog(
      DialogSpec(
        title: tr('Keyboard'),
        id: commandId,
        resizable: true,
        takesFocus: true,
        // Окно слушает реестр: правка меняет и клавиши, и то, у кого их
        // отняли, — а знает об этом он один.
        content: ListenableBuilder(
          listenable: registry,
          builder:
              (context, _) => FcKeyBindings(
                items: _items(registry, context),
                occupiedBy: (id, keys) => _occupiedBy(registry, id, keys, context),
                onAssign: (id, keys) => _assign(app, registry, id, keys),
                onClear: (id) => _assign(app, registry, id, ''),
                onReset: (id) => _reset(app, id),
                onResetAll: () => app.setKeyOverrides(const []),
              ),
        ),
        onSubmit: close,
        onDismiss: close,
      ),
    );
  }

  /// Строки окна: по строке на **привязку** плюс команды, у которых её нет.
  List<KeyBindingItem> _items(CommandRegistry registry, BuildContext context) {
    final strings = StringsScope.of(context);
    final commands = {for (final command in registry.installed) command.id: command};
    final effective = registry.bindings;
    final items = <KeyBindingItem>[];
    final bound = <String>{};

    for (var at = 0; at < registry.declaredBindings.length; at++) {
      final declared = registry.declaredBindings[at];
      final command = commands[declared.commandId];
      if (command == null) {
        // Привязка к команде, которой нет: модуль выключили. Показывать нечего.
        continue;
      }
      bound.add(command.id);
      final keys = at < effective.length ? effective[at].keys : declared.keys;
      items.add(
        KeyBindingItem(
          id: _idOf(declared),
          command: command.id,
          label: command.label,
          description: command.description,
          owner: registry.ownerOf(command.id),
          details: _detailsOf(declared),
          keys: keys == KeyCombination.none ? '' : keys.toString(),
          defaultKeys: declared.keys.toString(),
          cannotEdit:
              declared.keys == KeyCombination.anyCharacter
                  ? strings.tr('This one answers any letter: there is no combination to set')
                  : '',
        ),
      );
    }

    // Команды без привязок: знать, что они есть и вызываются из палитры,
    // полезнее, чем не знать (`docs/spec/key-bindings.md`, §2).
    for (final command in registry.installed) {
      if (bound.contains(command.id)) {
        continue;
      }
      items.add(
        KeyBindingItem(
          id: '${command.id}|',
          command: command.id,
          label: command.label,
          description: command.description,
          owner: registry.ownerOf(command.id),
          keys: '',
          defaultKeys: '',
          cannotEdit: strings.tr('This command has no key of its own yet — it is run from the palette'),
        ),
      );
    }
    return items;
  }

  /// Кто держит эту комбинацию **в том же месте**; null — никто.
  ///
  /// Разные места не спорят: `F5` в панели копирует, в просмотрщике
  /// форматирует (`docs/spec/key-bindings.md`, §3).
  String? _occupiedBy(CommandRegistry registry, String id, String keys, BuildContext context) {
    final combination = KeyCombination.tryParse(keys);
    final mine = _bindingOf(registry, id);
    if (combination == null || mine == null) {
      return null;
    }
    final probe = mine.withKeys(combination);
    for (var at = 0; at < registry.bindings.length; at++) {
      final other = registry.bindings[at];
      if (_idOf(registry.declaredBindings[at]) == id || !other.conflictsWith(probe)) {
        continue;
      }
      return registry.find(other.commandId)?.label ?? other.commandId;
    }
    return null;
  }

  /// Назначить привязке клавишу — и отнять её у того, кто держал.
  void _assign(Application app, CommandRegistry registry, String id, String keys) {
    final overrides = [...app.keyOverrides];
    // У прежнего держателя клавиша снимается: спор за одно нажатие решается
    // здесь, а не молча во время нажатия.
    if (keys.isNotEmpty) {
      for (var at = 0; at < registry.bindings.length; at++) {
        final declared = registry.declaredBindings[at];
        if (_idOf(declared) == id) {
          continue;
        }
        if (registry.bindings[at].keys.toString() == keys) {
          _put(overrides, declared, '');
        }
      }
    }

    final declared = _bindingOf(registry, id);
    if (declared != null) {
      _put(overrides, declared, keys);
    }
    app.setKeyOverrides(overrides);
  }

  /// Вернуть умолчание одной привязке: забыть о ней запись.
  void _reset(Application app, String id) {
    app.setKeyOverrides([
      for (final override in app.keyOverrides)
        if ('${override.command}|${override.was}' != id) override,
    ]);
  }

  /// Записать переназначение, заменив прежнее той же привязки.
  static void _put(List<KeyOverride> overrides, KeyBinding declared, String keys) {
    final was = declared.keys.toString();
    overrides
      ..removeWhere((item) => item.command == declared.commandId && item.was == was)
      // Умолчание записью не считается: вернуть его — значит забыть запись.
      ..addAll(keys == was ? const [] : [KeyOverride(command: declared.commandId, was: was, now: keys)]);
  }

  KeyBinding? _bindingOf(CommandRegistry registry, String id) =>
      registry.declaredBindings.where((binding) => _idOf(binding) == id).firstOrNull;

  /// Привязка опознаётся командой и **объявленной** комбинацией.
  static String _idOf(KeyBinding declared) => '${declared.commandId}|${declared.keys}';

  /// Чем эта привязка отличается от соседних у той же команды.
  static String _detailsOf(KeyBinding binding) =>
      binding.parameters.isEmpty ? '' : binding.parameters.values.map((value) => '$value').join(', ');
}
