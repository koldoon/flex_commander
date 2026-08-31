import 'dart:io';

import 'package:fc_api/fc_api.dart';

/// Переводит ошибку `dart:io` в ошибку дерева.
///
/// Платформенное по существу: коды у систем разные, и таблица их соответствий —
/// ровно то, что придётся дописывать, когда дойдут руки до третьей.
FsError fsErrorFrom(String path, FileSystemException error) {
  final code = error.osError?.errorCode;
  final kind =
      Platform.isWindows
          ? switch (code) {
            2 || 3 => FsErrorKind.notFound, // ERROR_FILE_NOT_FOUND, ERROR_PATH_NOT_FOUND
            5 => FsErrorKind.permissionDenied, // ERROR_ACCESS_DENIED
            267 => FsErrorKind.notADirectory, // ERROR_DIRECTORY
            _ => FsErrorKind.io,
          }
          : switch (code) {
            2 => FsErrorKind.notFound, // ENOENT
            13 => FsErrorKind.permissionDenied, // EACCES
            20 => FsErrorKind.notADirectory, // ENOTDIR
            _ => FsErrorKind.io,
          };
  return FsError(path, kind, error);
}
