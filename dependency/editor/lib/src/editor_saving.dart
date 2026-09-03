import 'dart:convert';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';

/// Сохранение текста — работа ядра.
///
/// Живёт там, где файл: временный файл, перенос прав и переименование — всё это
/// про источник, и решать, как правильно писать, полагается той стороне, где он
/// живёт. Экран приносит только текст (`docs/spec/client-server.md`, §6.2).
///
/// Текст целиком, а не кусками: правят его в памяти, и редактор всё равно
/// держит весь файл. Кусочная запись с подтверждением понадобится тому, кто
/// пишет больше, чем помещается, — а такой сегодня один, сборка архивов, и она
/// целиком по эту сторону границы.
abstract final class EditorSaving {
  /// Имя работы: под ним её и зовут из команды.
  static const String kind = 'editor.save';

  /// Что записать.
  static const String textOption = 'text';

  static Operation<OperationInputs, void> operation() =>
      TaskOperation<OperationInputs, void>((op, inputs) => _save(inputs));
}

/// Записывает содержимое экрана в файл.
///
/// Через временный файл и переименование там, где источник — настоящая
/// файловая система: `openWrite` обрезает файл сразу, и обрыв на середине
/// оставил бы половину вместо целого. Там, где переименования нет (архив
/// пересобирается целиком, сервер пишет потоком), запись идёт напрямую — там
/// целостность обеспечивает сам источник.
Future<void> _save(OperationInputs inputs) async {
  final node = inputs.targets.singleOrNull;
  if (node == null) {
    throw const FsError('', FsErrorKind.notFound);
  }
  final parent = node.parentDirectory;
  final provider = node.provider;

  if (parent == null || provider is! FileContentReceiver) {
    throw FsError(node.pathString, FsErrorKind.notSupported);
  }

  final bytes = utf8.encode(inputs.option<String>(EditorSaving.textOption) ?? '');
  final atomic = provider.capabilities.realFileSystem && provider is NodeEditor;

  if (!atomic) {
    await _write(provider as FileContentReceiver, parent, node.name, bytes);
    return;
  }

  // Имя со скрывающей точкой: временный файл не должен мозолить глаза в
  // панели, если сохранение всё же оборвётся.
  final temporary = '.${node.name}.fc-save';
  final editor = provider as NodeEditor;

  await _write(provider as FileContentReceiver, parent, temporary, bytes);
  try {
    final written = await editor.lookup(parent, temporary);
    if (written == null) {
      throw FsError(node.pathString, FsErrorKind.io);
    }

    // Режим цели переносится на временный **до** переименования: иначе новый
    // файл встал бы на её место со своими правами по умолчанию, и `600`
    // молча превратилось бы в `644`. Заметить такое можно очень нескоро.
    //
    // Владельца это не переносит и не может: сменить его без прав
    // администратора нельзя. Там, где владелец чужой, запись и так идёт через
    // повышение, а `cp` пишет в существующий файл и сохраняет обоих.
    if (provider is NodeAttributesWriter) {
      await (provider as NodeAttributesWriter).carryMode(from: node, to: written);
    }

    if (!await editor.renameEntry(written, parent, node.name)) {
      throw FsError(node.pathString, FsErrorKind.io);
    }
  } on Object {
    // Недописанное под своим именем выглядело бы как целый файл.
    final leftover = await editor.lookup(parent, temporary);
    if (leftover != null) {
      await editor.deleteEntry(leftover);
    }
    rethrow;
  }
}

Future<void> _write(FileContentReceiver receiver, DirectoryNode parent, String name, List<int> bytes) async {
  final sink = await receiver.openWrite(parent, name, length: bytes.length);
  await sink.addStream(Stream<List<int>>.value(bytes));
  await sink.close();
}
