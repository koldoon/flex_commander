import 'package:fc_ui_api/fc_ui_api.dart';

import 'transfer_commands.dart';

/// Команды файлового буфера обмена (`docs/spec/file-clipboard.md`).
///
/// Служба спрашивается **у контекста, а не берётся в конструкторе**: её ставит
/// модуль, а порядок установки модулей — не дело команды. Нет службы — команда
/// невыполнима, клавиша честно ничего не делает, и сборка приложения от этого
/// не падает.
abstract class ClipboardCommandBase extends AppCommand {
  ClipboardCommandBase(this.env);

  final FcContext env;

  FileClipboard? get clipboard => env.resolveAll<FileClipboard>().firstOrNull;
}

/// Положить помеченное в буфер.
abstract class ClipboardPutCommand extends ClipboardCommandBase {
  ClipboardPutCommand(super.env);

  /// Кладём с намерением перенести.
  bool get moves;

  @override
  bool isExecutable(CommandContext context) => clipboard != null && context.session.hasTargets;

  @override
  Future<void> execute(CommandContext context) async {
    final buffer = clipboard;
    if (buffer == null) {
      return;
    }
    // Цели спрашиваются у ядра: помеченное бывает и в соседних ветвях дерева,
    // и строк его в списке нет вовсе (`docs/spec/operation-targets.md`, §4).
    final targets = await context.session.allTargets();
    if (targets.isEmpty) {
      return;
    }

    await buffer.writeFiles(targets, move: moves);

    // Буфер — место невидимое, и нажатие без ответа неотличимо от промаха.
    final strings = context.app.strings;
    context.app.toasts.show(
      moves
          ? strings.plural(targets.length, one: '{n} item ready to move', other: '{n} items ready to move')
          : strings.plural(targets.length, one: 'Copied {n} item', other: 'Copied {n} items'),
    );
  }
}

/// `Cmd-C`: помеченное — в буфер.
class ClipboardCopyCommand extends ClipboardPutCommand {
  ClipboardCopyCommand(super.env);

  static const String commandId = 'file.clipboard.copy';

  @override
  String get id => commandId;

  @override
  String get label => tr('Copy to clipboard');

  @override
  String get description => tr('Put the selected items into the clipboard');

  /// «Буфер» в названии уже есть — в синонимах ему делать нечего. Здесь то,
  /// чем команду зовут, но чего в названии нет.
  @override
  Set<String> get keywords => const {'buffer', 'take'};

  @override
  bool get moves => false;
}

/// `Cmd-X`: то же, с намерением перенести.
///
/// Ничего не удаляет и ничего не блокирует: объекты уходят из источника только
/// при вставке и только те, которые действительно перенеслись
/// (`docs/spec/file-clipboard.md`, §5).
class ClipboardCutCommand extends ClipboardPutCommand {
  ClipboardCutCommand(super.env);

  static const String commandId = 'file.clipboard.cut';

  @override
  String get id => commandId;

  @override
  String get label => tr('Cut to clipboard');

  @override
  String get description => tr('Put the selected items into the clipboard to be moved');

  @override
  Set<String> get keywords => const {'buffer', 'move'};

  @override
  bool get moves => true;
}

/// `Cmd-V` и `Alt-Cmd-V`: вставить в каталог активной панели.
///
/// Работа идёт теми же `file.copy` и `file.move`: у них уже есть параметры для
/// задания, пришедшего **готовым**, — те же, которыми работает бросок мышью.
/// Второго пути копирования в приложении не появляется.
class ClipboardPasteCommand extends ClipboardCommandBase {
  ClipboardPasteCommand(super.env, {required this.forcesMove});

  static const String copyId = 'file.clipboard.paste';
  static const String moveId = 'file.clipboard.pasteMove';

  /// Вставить переносом, что бы ни лежало в буфере, — привычка Finder
  /// («Move Items Here»).
  final bool forcesMove;

  @override
  String get id => forcesMove ? moveId : copyId;

  @override
  String get label => forcesMove ? tr('Paste as move') : tr('Paste');

  @override
  String get description =>
      forcesMove ? tr('Move the clipboard items into this panel') : tr('Put the clipboard items into this panel');

  @override
  Set<String> get keywords => forcesMove ? const {'clipboard', 'buffer'} : const {'clipboard', 'buffer', 'move'};

  /// Про **приёмник**, а не про буфер: что в буфере, спрашивают у системы, а
  /// ответа этот вопрос ждать не может — он задаётся на каждую перерисовку
  /// ряда кнопок. Пустой буфер честно скажет о себе при нажатии (§10).
  @override
  bool isExecutable(CommandContext context) {
    final panel = context.session;
    return clipboard != null && !panel.busy && panel.source.canWrite && panel.currentPath.isNotEmpty;
  }

  @override
  Future<void> execute(CommandContext context) async {
    final buffer = clipboard;
    if (buffer == null) {
      return;
    }
    final files = await buffer.readFiles();
    if (files == null || files.isEmpty) {
      // Молчания на нажатие быть не должно: невидимый буфер и промах по
      // клавише выглядят одинаково.
      context.app.toasts.show(tr('The clipboard has no files'));
      return;
    }

    // Намерение переносить живёт в буфере, но `Alt-Cmd-V` сильнее: человек
    // сказал прямо.
    final moves = forcesMove || files.move;
    // Через реестр, а не напрямую: там снимается полоса быстрого поиска и там
    // же разбирается исход — ошибка работы без окна иначе пропала бы совсем.
    // Ждать нечего: работа рассказывает о себе сама — окном, полосой и строкой
    // состояния, как и всякая другая.
    context.app.commands.run(
      moves ? MoveCommand.commandId : CopyCommand.commandId,
      CommandInvocation(
        parameters: {
          TransferCommandBase.sourcesParam: files.addresses,
          TransferCommandBase.destinationParam: context.session.currentPath,
        },
      ),
    );
  }
}
