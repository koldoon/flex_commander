import 'dart:typed_data';
import 'dart:ui';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import 'pdf_viewer_settings.dart';

/// Прочитанный документ: ручка в системе и размеры его страниц.
class PdfDocument {
  PdfDocument(this.handle);

  /// Документ в системе. Рисует, ищет и отдаёт текст он.
  final SystemPdfDocument handle;

  /// Показанные размеры страниц, в пунктах.
  List<Size> get pages => handle.pages;

  int get pageCount => pages.length;

  /// Читает файл и отдаёт его системе.
  ///
  /// Отказ — [ViewerRefused] с причиной словами, и каждая называет выход:
  /// системный просмотр открывает то, чего не умеем мы
  /// (`docs/spec/pdf-viewer.md`, §5).
  static Future<PdfDocument> read(
    FileEntry entry,
    Content content,
    PdfViewerSettings settings, {
    required SystemPdf? system,
    required Future<void> Function() checkpoint,
    Strings? strings,
  }) async {
    final said = strings ?? StringsRegistry();

    // Без службы не рисует никто. Отдать файл текстовому значило бы снова
    // показать поток байтов — поэтому отказ, а не «не мой файл».
    if (system == null) {
      throw ViewerRefused(said.tr('PDF viewing needs the system service — open it with the system (Cmd-O)'));
    }

    if (entry.size > settings.maxFileSize) {
      throw ViewerRefused(
        said.tr(
          'PDF is too large: {size}, limit is {limit} — open it with the system (Cmd-O)',
          args: {'size': formatBytesLong(entry.size), 'limit': formatBytesLong(settings.maxFileSize)},
        ),
      );
    }

    final bytes = BytesBuilder(copy: false);
    await for (final chunk in content.read()) {
      // Курсор в быстром просмотре мог уйти дальше: дочитывать незачем.
      await checkpoint();
      bytes.add(chunk);
    }
    await checkpoint();

    final handle = await system.open(bytes.takeBytes());
    if (handle == null) {
      throw ViewerRefused(said.tr('Not a PDF, or the file is damaged (Cmd-O opens it with the system)'));
    }

    // Курсор ушёл, пока система разбирала: документ уже никому не нужен, а
    // открытым в раннере он остался бы навсегда.
    try {
      await checkpoint();
    } on Object {
      await handle.close();
      rethrow;
    }

    if (handle.locked) {
      await handle.close();
      throw ViewerRefused(said.tr('This PDF is password-protected — open it with the system (Cmd-O)'));
    }
    if (handle.pages.isEmpty) {
      await handle.close();
      throw ViewerRefused(said.tr('Not a PDF, or the file is damaged (Cmd-O opens it with the system)'));
    }

    return PdfDocument(handle);
  }

  Future<void> close() => handle.close();
}
