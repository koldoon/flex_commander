import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

/// Адрес объекта — строкой в буфер обмена (`docs/spec/file-clipboard.md`, §7).
///
/// Спрашивают каждый день: сослаться на файл в письме, вставить путь в
/// терминал, приложить к задаче.
///
/// Файлового буфера ей не нужно — хватает текстового. Поэтому команда работает
/// и там, где буфера файлов нет вовсе.
///
/// Буфер спрашивается **у контекста, а не в конструкторе**: службы ставятся
/// модулями, и порядок их установки — не наше дело. Нет буфера — команда
/// невыполнима, и клавиша честно ничего не делает, вместо того чтобы уронить
/// сборку приложения.
class CopyPathCommand extends AppCommand {
  CopyPathCommand(this.env);

  static const String commandId = 'file.copyPath';

  final FcContext env;

  ClipboardService? get _clipboard => env.resolveAll<ClipboardService>().firstOrNull;

  @override
  String get id => commandId;

  @override
  String get label => tr('Copy path');

  @override
  String get description => tr('Copy the address of the selected items to the clipboard');

  /// Ищется теми словами, какими её называют: «путь», «адрес», «ссылка».
  @override
  Set<String> get keywords => const {'clipboard', 'address', 'pathname', 'link', 'location'};

  @override
  bool isExecutable(CommandContext context) => _clipboard != null && context.session.hasTargets;

  @override
  Future<void> execute(CommandContext context) async {
    // Цели спрашиваются у ядра: помеченное бывает и в соседних ветвях дерева, и
    // строк их в списке нет вовсе (`docs/spec/operation-targets.md`, §4).
    // Команде это по карману — она не кадр рисует.
    final clipboard = _clipboard;
    final targets = await context.session.allTargets();
    if (clipboard == null || targets.isEmpty) {
      return;
    }

    // По адресу на строку: так их и вставляют — в терминал, в письмо, в задачу.
    final addresses = [for (final entry in targets) addressOf(entry)];
    await clipboard.writeText(addresses.join('\n'));

    // Буфер — место невидимое, и нажатие без ответа неотличимо от промаха.
    context.app.toasts.show(
      context.app.strings.plural(addresses.length, one: 'Copied {n} address', other: 'Copied {n} addresses'),
    );
  }
}

/// Адрес строки — тот, который показывает панель.
///
/// Машинный адрес несёт схемы провайдеров (`/home/a.zip:zip:/inner`), и
/// вставить его некуда: ни в терминал, ни в письмо, — а читается он как ошибка.
/// Показанный же адрес у местного файла и есть его путь, у сервера — `ssh://…`,
/// внутри архива — путь, где архив стоит обычным звеном.
///
/// Складывается из каталога строки и её имени: каталог приезжает **показанным**
/// (`FileEntry.directoryPath`), а разделитель у показанных адресов один — косая
/// черта, чьим бы источником строка ни была.
String addressOf(FileEntry entry) {
  final directory = entry.directoryPath;
  if (directory.isEmpty) {
    return entry.name;
  }
  return directory.endsWith('/') ? '$directory${entry.name}' : '$directory/${entry.name}';
}
