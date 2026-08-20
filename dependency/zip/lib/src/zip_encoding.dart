import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:fc_api/fc_api.dart';

import 'counting_input_stream.dart';

/// Что положить в архив: одна запись.
///
/// Простые значения, а не узлы: задание уходит в изолят, и провайдеры туда не
/// переезжают. Дерево обходит главный изолят — он же решает, что делать со
/// ссылками, — а сюда приходит уже готовый список.
class ZipEntry {
  const ZipEntry.file(this.name, this.path) : isDirectory = false;

  const ZipEntry.directory(this.name) : path = null, isDirectory = true;

  /// Имя внутри архива.
  final String name;

  /// Путь к содержимому на диске; null у каталога.
  final String? path;

  final bool isDirectory;
}

/// Собирает архив **в отдельном изоляте**.
///
/// Сжатие в `archive` синхронное: `ZipEncoder.add` дожимает запись до конца, ни
/// разу не отдав управление. На большом дереве это значит, что кадры не выходят
/// вовсе — приложение висит наглухо, вплоть до системного «не отвечает». Снято
/// со стека живого процесса: главный изолят стоял в `_ZLibEncoder.encodeStream`.
///
/// Поэтому вся тяжёлая работа уезжает в изолят, а обратно идут только числа:
/// какая запись началась и сколько байт прошло.
Future<void> encodeZipArchive({
  required String archivePath,
  required List<ZipEntry> entries,
  required int level,
  required TaskOperation<void> op,
  void Function(String name, int? bytes)? onEntry,
  void Function(String name)? onEntryDone,
  void Function(int bytes)? onBytes,
}) async {
  final ReceivePort port = ReceivePort();
  final Completer<void> done = Completer<void>();

  final Isolate isolate = await Isolate.spawn(
    _encode,
    _EncodeRequest(port.sendPort, archivePath, entries, level),
    // Ошибку и внезапную смерть изолята мы обрабатываем сами: без этого они
    // ушли бы в необработанные и работа осталась бы висеть.
    onError: port.sendPort,
    onExit: port.sendPort,
    errorsAreFatal: true,
  );

  late final StreamSubscription<dynamic> subscription;
  subscription = port.listen((dynamic message) {
    switch (message) {
      case _EntryStarted(:final name, :final bytes):
        onEntry?.call(name, bytes);
      case _EntryDone(:final name):
        onEntryDone?.call(name);
      case _BytesRead(:final bytes):
        onBytes?.call(bytes);
      case _Finished():
        if (!done.isCompleted) {
          done.complete();
        }
      case _Failed(:final message):
        if (!done.isCompleted) {
          done.completeError(FsError(archivePath, FsErrorKind.io, message));
        }
      default:
        // `onExit` присылает null, `onError` — список [ошибка, стек]. И то и
        // другое значит, что архив не собран.
        if (!done.isCompleted) {
          done.completeError(FsError(archivePath, FsErrorKind.io, message));
        }
    }
  });

  try {
    // Отмена не ждёт конца записи: изолят снимается, а недописанный архив
    // лежит во временном каталоге и уходит вместе с ним.
    //
    // Именно `checkpoint`, а не `checkCanceled`: кнопка «Cancel» только
    // **просит** прервать, а вопрос «Abort the operation?» и сама отмена
    // происходят в нём. Пока тело операции стоит в ожидании изолята, звать его
    // больше некому — и без этого кнопка не делала ничего.
    while (true) {
      await op.checkpoint();
      final bool finished = await Future.any([
        done.future.then((_) => true),
        // Сто миллисекунд — предел задержки между нажатием «Cancel» и
        // вопросом: чаще незачем, реже уже заметно.
        Future<bool>.delayed(const Duration(milliseconds: 100), () => false),
      ]);
      if (finished) {
        break;
      }
    }
  } finally {
    await subscription.cancel();
    port.close();
    isolate.kill(priority: Isolate.immediate);
  }
}

/// Тело изолята: тот же код, что был в команде, только без интерфейса.
void _encode(_EncodeRequest request) {
  final SendPort port = request.port;
  final List<InputFileStream> opened = [];
  OutputFileStream? output;

  try {
    output = OutputFileStream(request.archivePath);
    final ZipEncoder encoder = ZipEncoder()..startEncode(output, level: request.level);

    for (final entry in request.entries) {
      if (entry.isDirectory) {
        // Пустой каталог иначе пропал бы: в zip он существует только записью.
        encoder.add(ArchiveFile.directory('${entry.name}/'));
        port.send(_EntryDone(entry.name));
        continue;
      }

      final File file = File(entry.path!);
      final int size = file.existsSync() ? file.lengthSync() : -1;
      // Дважды: упаковщик читает запись ради контрольной суммы, а потом ради
      // сжатия — и второй проход занимает куда больше времени.
      port.send(_EntryStarted(entry.name, size < 0 ? null : size * 2));

      final InputFileStream content = InputFileStream(entry.path!);
      opened.add(content);
      encoder.add(
        ArchiveFile.stream(entry.name, CountingInputStream(content, (bytes) => port.send(_BytesRead(bytes)))),
      );
      port.send(_EntryDone(entry.name));
    }

    encoder.endEncode();
    port.send(const _Finished());
  } on ArchiveException catch (error) {
    port.send(_Failed(error.toString()));
  } on FileSystemException catch (error) {
    port.send(_Failed(error.message));
  } finally {
    output?.closeSync();
    for (final stream in opened) {
      stream.closeSync();
    }
  }
}

class _EncodeRequest {
  const _EncodeRequest(this.port, this.archivePath, this.entries, this.level);

  final SendPort port;
  final String archivePath;
  final List<ZipEntry> entries;
  final int level;
}

/// Началась очередная запись.
class _EntryStarted {
  const _EntryStarted(this.name, this.bytes);

  final String name;
  final int? bytes;
}

/// Запись готова — она и есть обработанный объект.
///
/// Отмечает её упаковщик, а не обход: обход только составляет список, и
/// считать по нему сделанное значило бы показывать «2000 из 2000», пока файлы
/// ещё бегут.
class _EntryDone {
  const _EntryDone(this.name);

  final String name;
}

/// Прочитаны очередные байты.
class _BytesRead {
  const _BytesRead(this.bytes);

  final int bytes;
}

class _Finished {
  const _Finished();
}

class _Failed {
  const _Failed(this.message);

  final String message;
}
