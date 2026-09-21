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
        title: 'Key bindings',
        id: commandId,
        resizable: true,
        takesFocus: true,
        ownWidth: true,
        // Та же форма, что и у настроек: она принимает произвольные разделы, и
        // второй такой писать незачем (`docs/spec/key-bindings.md`, §8).
        content: FcSettingsForm(pages: _pages(app), onClose: close, searchHint: 'Search commands'),
        onSubmit: close,
        onDismiss: close,
      ),
    );
  }

  /// Разделы: по одному на контекст, пустых нет.
  List<SettingsPage> _pages(Application app) {
    final registry = _registry();
    final rows = _rows(registry);
    return [
      for (final context in KeyContext.values)
        if (rows.where((row) => row.context == context).toList() case final own when own.isNotEmpty)
          SettingsPage(
            title: context.title,
            build:
                () => SettingsSchema([
                  // «Вернуть всё» стоит первым полем первого раздела: своего
                  // ряда кнопок у формы настроек нет.
                  if (context == rows.first.context)
                    SettingsField.button(
                      'keys.resetAll',
                      title: 'Your keys',
                      description: 'Forget every key you have changed',
                      label: 'Reset all keys',
                      run: () => app.setKeyOverrides(const []),
                    ),
                  for (final row in own) _field(app, registry, row),
                ], save: () {}),
          ),
    ];
  }

  SettingsKeys _field(Application app, CommandRegistry registry, _Row row) {
    final command = registry.find(row.commandId);
    final label = command?.label ?? row.commandId;
    final description = command?.description ?? '';
    return SettingsField.keys(
      row.commandId,
      // Значения привязки — в подписи: `Cmd-2` и `Cmd-3` это одна команда «вид
      // панели», и шесть строк с одним названием различить было бы нечем.
      title: row.details.isEmpty ? label : '$label: ${row.details}',
      description: description,
      keywords: command?.keywords ?? const {},
      read: () => row.keysIn(registry.bindings),
      defaultKeys: row.keysIn(registry.declaredBindings),
      reset: () => _reset(app, registry, row),
      edit:
          () => _edit(
            app,
            registry,
            row,
            command: row.details.isEmpty ? label : '$label: ${row.details}',
            context: row.context.title,
          ),
    );
  }

  /// Строки окна: команда в своём контексте, ровно один раз.
  ///
  /// Группировка по тройке «команда, контекст, значения»: `Esc` просмотрщика,
  /// объявленный дважды — для полного экрана и для быстрого просмотра, — это
  /// одно дело и одна строка (`docs/spec/key-bindings.md`, §3).
  List<_Row> _rows(CommandRegistry registry) {
    final rows = <String, _Row>{};
    final declared = registry.declaredBindings;
    for (var at = 0; at < declared.length; at++) {
      final binding = declared[at];
      final context = binding.context;
      // Внутренняя привязка: её не показывают и не переназначают.
      if (context == null || registry.find(binding.commandId) == null) {
        continue;
      }
      final details = _detailsOf(binding);
      final key = '${binding.commandId}|${context.name}|$details';
      (rows[key] ??= _Row(commandId: binding.commandId, context: context, details: details)).at.add(at);
    }
    return rows.values.toList(growable: false);
  }

  /// Открыть окошко записи поверх окна клавиш и дождаться, пока его закроют.
  Future<void> _edit(
    Application app,
    CommandRegistry registry,
    _Row row, {
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

    dialogId = view.showDialog(
      DialogSpec(
        title: 'Key binding',
        content: ListenableBuilder(
          listenable: registry,
          builder:
              (_, _) => FcKeyRecorder(
                command: command,
                context: context,
                read: () => row.keysIn(registry.bindings),
                defaultKeys: row.keysIn(registry.declaredBindings),
                occupiedBy: (keys) => _occupiedBy(registry, row, keys),
                onAssign: (keys) => _assign(app, registry, row, keys),
                onClear: () => _assign(app, registry, row, ''),
                onReset: () => _reset(app, registry, row),
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
  String? _occupiedBy(CommandRegistry registry, _Row row, String keys) {
    final combination = KeyCombination.tryParse(keys);
    if (combination == null) {
      return null;
    }
    final probe = registry.declaredBindings[row.at.first].withKeys(combination);
    for (var at = 0; at < registry.bindings.length; at++) {
      if (row.at.contains(at) || !registry.bindings[at].conflictsWith(probe)) {
        continue;
      }
      final other = registry.bindings[at];
      return registry.find(other.commandId)?.label ?? other.commandId;
    }
    return null;
  }

  /// Назначить строке клавишу — и отнять её у того, кто держал.
  ///
  /// У строки привязок бывает несколько (`F8` и `Cmd-Bsp` у удаления): клавишу
  /// получает первая, у остальных она снимается. Так «одна клавиша на дело»
  /// получается ровно тогда, когда человек её записал, а не отбирается у него
  /// заранее (`docs/spec/key-bindings.md`, §10).
  void _assign(Application app, CommandRegistry registry, _Row row, String keys) {
    final overrides = [...app.keyOverrides];
    final declared = registry.declaredBindings;

    if (keys.isNotEmpty) {
      final combination = KeyCombination.parse(keys);
      final probe = declared[row.at.first].withKeys(combination);
      for (var at = 0; at < registry.bindings.length; at++) {
        if (row.at.contains(at) || !registry.bindings[at].conflictsWith(probe)) {
          continue;
        }
        _put(overrides, declared[at], '');
      }
    }

    for (final (index, at) in row.at.indexed) {
      _put(overrides, declared[at], index == 0 ? keys : '');
    }
    app.setKeyOverrides(overrides);
  }

  /// Вернуть умолчание: забыть записи обо всех привязках строки.
  void _reset(Application app, CommandRegistry registry, _Row row) {
    final forget = {
      for (final at in row.at) '${registry.declaredBindings[at].commandId}|${registry.declaredBindings[at].keys}',
    };
    app.setKeyOverrides([
      for (final override in app.keyOverrides)
        if (!forget.contains('${override.command}|${override.was}')) override,
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

  /// Чем эта привязка отличается от соседних у той же команды.
  static String _detailsOf(KeyBinding binding) =>
      binding.parameters.isEmpty ? '' : binding.parameters.values.map((value) => '$value').join(', ');
}

/// Строка окна: команда в своём контексте со своими значениями.
class _Row {
  _Row({required this.commandId, required this.context, required this.details});

  final String commandId;
  final KeyContext context;

  /// Значения, с которыми команда запускается: ими и различаются соседние
  /// строки одной команды.
  final String details;

  /// Места объявленных привязок строки — они же места действующих: реестр
  /// держит оба списка одной длины и в одном порядке.
  final List<int> at = [];

  /// Чем строку вызывают в этом списке привязок; пусто — ничем.
  String keysIn(List<KeyBinding> bindings) =>
      [for (final index in at) bindings[index].keys].where((keys) => keys != KeyCombination.none).join(', ');
}
