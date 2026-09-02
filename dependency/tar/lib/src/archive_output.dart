import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';

/// Отдаёт готовый архив приёмнику байтовым контрактом.
///
/// Общее у обеих команд модуля — и это единственное, что у них общее: `Mk Tar`
/// собирает дерево, `Mk Gz` жмёт один поток, а вот кончаются они одинаково.
/// Прямо в приёмник ни та, ни другая писать не может: размер готового архива
/// до последнего байта неизвестен, а приёмник вправе его требовать.
///
/// Второе плечо работы: байты уже собранного архива уходят туда, где ему
/// лежать. На диске оно быстрое, по сети — дольше первого.
Future<void> deliverArchive(
  String archivePath,
  DirectoryNode destination,
  String name,
  TaskOperation<Object?, void> op,
  TransferProgress progress,
) async {
  final provider = destination.provider;
  if (provider is! FileContentReceiver) {
    throw FsError(destination.pathString, FsErrorKind.notSupported);
  }

  final file = File(archivePath);
  final length = await file.length();
  final sink = await (provider as FileContentReceiver).openWrite(destination, name, length: length);

  try {
    progress.startSource(name);
    final item = progress.startItem(name, bytes: length);
    await sink.addStream(
      file.openRead().asyncMap((chunk) async {
        await op.checkpoint();
        progress.advanceBytes(chunk.length, item);
        return chunk;
      }),
    );
    await sink.close();
    progress.finishItem(item);
  } on Object {
    await sink.close().catchError((Object _) {});
    rethrow;
  }
}
