import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';

/// Всё, что приложение умеет **сейчас**, — списком с поиском.
///
/// Заводится не ради удобства: команда, которой не досталось клавиши, до сих
/// пор была невидима и невызываема — а клавиш меньше, чем команд, и с каждым
/// модулем разрыв растёт. Палитра закрывает это свойство устройства целиком.
class CommandPaletteCommand extends AppCommand {
  CommandPaletteCommand({required CommandRegistry Function() registry, required this.recent, required this.save})
    : _registry = registry;

  /// Реестр — способом его спросить: во время создания команды его ещё нет.
  final CommandRegistry Function() _registry;

  /// Недавние: идентификаторы, свежие впереди.
  final List<String> Function() recent;

  final void Function() save;

  static const String commandId = 'app.commands';

  /// Сколько недавних помнится.
  static const int recentLimit = 10;

  @override
  String get id => commandId;

  @override
  String get label => 'Commands';

  @override
  String get description => 'Everything the application can do right now, by name';

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute(CommandContext context) async {
    final registry = _registry();
    final view = context.app.view;
    late final String dialogId;
    void close() => view.closeDialog(dialogId);

    dialogId = view.showDialog(
      DialogSpec(
        title: 'Commands',
        takesFocus: true,
        content: FcCommandPalette(
          items: _items(registry, context),
          recent: recent(),
          onRun: (commandId) {
            // Окно закрывается **до** запуска: у команды может быть своё, и
            // открывать его поверх палитры незачем.
            close();
            _remember(commandId);
            registry.run(commandId);
          },
        ),
        onDismiss: close,
      ),
    );
  }

  /// Только выполнимое сейчас.
  ///
  /// Палитра отвечает на вопрос «что мне доступно», а не «что бывает»:
  /// приглушённая строка, на которую нельзя нажать, здесь только мешает. Полный
  /// перечень остаётся в справке.
  List<PaletteItem> _items(CommandRegistry registry, CommandContext context) {
    return [
      for (final command in registry.installed)
        if (command.id != commandId && registry.isExecutable(command))
          PaletteItem(
            id: command.id,
            label: command.label,
            owner: registry.ownerOf(command.id),
            // Клавиши берутся у реестра, поэтому переназначение видно сразу и
            // разойтись с действительностью не может.
            keys: registry.bindingsOf(command.id).map((binding) => '${binding.keys}').join(', '),
            // Синонимы объявляет сама команда: про то, каким словом её будут
            // искать, знает модуль, а не палитра.
            keywords: command.keywords.toList(),
          ),
    ];
  }

  void _remember(String commandId) {
    final list =
        recent()
          ..remove(commandId)
          ..insert(0, commandId);
    if (list.length > recentLimit) {
      list.removeRange(recentLimit, list.length);
    }
    save();
  }
}
