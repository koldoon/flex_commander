import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:path/path.dart' as p;

import 'sftp_api.dart';
import 'sftp_sink.dart';

/// [SftpApi] поверх `dartssh2`.
///
/// Единственное место модуля, знающее про библиотеку и про протокол. Здесь же
/// ошибки SFTP переводятся в [FsError]: движок переноса и панель другого языка
/// не понимают, а «SftpStatusError(3)» в окне — это не ответ пользователю.
class DartsshSftp implements SftpApi {
  DartsshSftp(this._sftp);

  final SftpClient _sftp;

  @override
  Future<SftpEntry?> stat(String path, {bool followLink = false}) async {
    try {
      final attrs = await _sftp.stat(path, followLink: followLink);
      return _entry(p.posix.basename(path), attrs);
    } on SftpStatusError catch (error) {
      if (error.code == SftpStatusCode.noSuchFile) {
        // Не ошибка, а ответ: по этому пути ничего нет.
        return null;
      }
      throw _errorFrom(path, error);
    } on SftpError catch (error) {
      throw _errorFrom(path, error);
    }
  }

  @override
  Future<List<SftpEntry>> listDirectory(String path) async {
    try {
      final names = await _sftp.listdir(path);
      return [
        for (final name in names)
          if (name.filename != '.' && name.filename != '..') _entry(name.filename, name.attr),
      ];
    } on SftpError catch (error) {
      throw _errorFrom(path, error);
    }
  }

  @override
  Future<String?> readLink(String path) async {
    try {
      return await _sftp.readlink(path);
    } on SftpError {
      // Ссылка может быть битой или недоступной — это не повод обрывать
      // чтение каталога, в котором она лежит.
      return null;
    }
  }

  @override
  Future<void> makeDirectory(String path) async {
    try {
      await _sftp.mkdir(path);
    } on SftpError catch (error) {
      throw _errorFrom(path, error);
    }
  }

  @override
  Future<void> createLink(String path, String reference) async {
    try {
      // Порядок доводов у `dartssh2` такой же, как в самом протоколе: сперва
      // цель, потом путь новой ссылки. Имена в библиотеке названы наоборот,
      // поэтому здесь они и переставлены — проверено на живом сервере.
      await _sftp.link(reference, path);
    } on SftpError catch (error) {
      throw _errorFrom(path, error);
    }
  }

  @override
  Future<void> removeFile(String path) async {
    try {
      await _sftp.remove(path);
    } on SftpError catch (error) {
      throw _errorFrom(path, error);
    }
  }

  @override
  Future<void> removeDirectory(String path) async {
    try {
      await _sftp.rmdir(path);
    } on SftpError catch (error) {
      throw _errorFrom(path, error);
    }
  }

  @override
  Future<void> rename(String from, String to) async {
    try {
      await _sftp.rename(from, to);
    } on SftpError catch (error) {
      throw _errorFrom(from, error);
    }
  }

  @override
  Future<Stream<List<int>>> openRead(String path, {int offset = 0}) async {
    final SftpFile file;
    try {
      file = await _sftp.open(path);
    } on SftpError catch (error) {
      throw _errorFrom(path, error);
    }
    return _readAndClose(file, path, offset);
  }

  /// Файл закрывается вместе с концом потока — в том числе когда читать
  /// перестали на середине (отмена копирования).
  Stream<List<int>> _readAndClose(SftpFile file, String path, int offset) async* {
    try {
      yield* file.read(offset: offset);
    } on SftpError catch (error) {
      throw _errorFrom(path, error);
    } finally {
      try {
        await file.close();
      } on Object {
        // Закрытие уже неважно: файл прочитан или чтение прервано.
      }
    }
  }

  @override
  Future<StreamSink<List<int>>> openWrite(String path) async {
    try {
      final file = await _sftp.open(
        path,
        mode: SftpFileOpenMode.write | SftpFileOpenMode.create | SftpFileOpenMode.truncate,
      );
      return SftpFileSink(file, path);
    } on SftpError catch (error) {
      throw _errorFrom(path, error);
    }
  }

  @override
  Future<bool> canWriteTo(String path) async {
    SftpFile? file;
    try {
      // Ни `create`, ни `truncate`: спрашиваем, пустят ли, а не пишем.
      file = await _sftp.open(path, mode: SftpFileOpenMode.write);
      return true;
    } on SftpError {
      return false;
    } finally {
      try {
        await file?.close();
      } on Object {
        // Закрытие пробы уже неважно: ответ получен.
      }
    }
  }

  @override
  Future<String> absolute(String path) async {
    try {
      return await _sftp.absolute(path);
    } on SftpError catch (error) {
      throw _errorFrom(path, error);
    }
  }

  @override
  Future<void> close() async {
    _sftp.close();
  }

  SftpEntry _entry(String name, SftpFileAttrs attrs) {
    final type = _typeOf(attrs.mode);
    return SftpEntry(
      name: name,
      type: type,
      // У каталога размер — это размер самой записи каталога, а не того, что
      // в нём лежит: показывать его пользователю было бы ложью.
      size: type == FileType.directory ? FsNode.unknownSize : (attrs.size ?? FsNode.unknownSize),
      mode: attrs.mode?.value ?? 0,
      modified: _time(attrs.modifyTime),
      accessed: _time(attrs.accessTime),
    );
  }

  static DateTime? _time(int? seconds) => seconds == null ? null : DateTime.fromMillisecondsSinceEpoch(seconds * 1000);

  static FileType _typeOf(SftpFileMode? mode) => switch (mode?.type) {
    SftpFileType.directory => FileType.directory,
    SftpFileType.symbolicLink => FileType.symbolicLink,
    SftpFileType.regularFile => FileType.regular,
    SftpFileType.socket => FileType.socket,
    SftpFileType.pipe => FileType.fifo,
    SftpFileType.blockDevice => FileType.blockSpecial,
    SftpFileType.characterDevice => FileType.characterSpecial,
    _ => FileType.unknown,
  };

  /// Код состояния SFTP — видом ошибки дерева.
  ///
  /// Кодов в третьей версии протокола мало, и «уже существует» среди них нет:
  /// сервер отвечает общим `failure`. Поэтому существование проверяется до
  /// действия, а не по коду ответа — так же, как это делает локальный
  /// провайдер перед созданием каталога.
  static FsError _errorFrom(String path, SftpError error) {
    if (error is! SftpStatusError) {
      return FsError(path, FsErrorKind.io, error);
    }
    return FsError(path, switch (error.code) {
      SftpStatusCode.noSuchFile => FsErrorKind.notFound,
      SftpStatusCode.permissionDenied => FsErrorKind.permissionDenied,
      SftpStatusCode.opUnsupported => FsErrorKind.notSupported,
      _ => FsErrorKind.io,
    }, error);
  }
}
