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
    PdfPasswords? passwords,
    Credentials? credentials,
    bool mayAsk = false,
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
      try {
        await _unlock(handle, entry, said, checkpoint, passwords, credentials, mayAsk: mayAsk);
      } on Object {
        await handle.close();
        rethrow;
      }
    }
    if (handle.pages.isEmpty) {
      await handle.close();
      throw ViewerRefused(said.tr('Not a PDF, or the file is damaged (Cmd-O opens it with the system)'));
    }

    return PdfDocument(handle);
  }

  Future<void> close() => handle.close();

  /// Отпереть: названным в этом сеансе паролем, а нет его — спросить
  /// (`docs/spec/pdf-viewer.md`, §15).
  ///
  /// Спрашивает только [mayAsk] — `F3`. Быстрый просмотр не спрашивает
  /// никогда: окно, выскакивающее от шага курсора, — ловушка.
  static Future<void> _unlock(
    SystemPdfDocument handle,
    FileEntry entry,
    Strings said,
    Future<void> Function() checkpoint,
    PdfPasswords? passwords,
    Credentials? credentials, {
    required bool mayAsk,
  }) async {
    final realm = PdfPasswords.realmOf(entry);

    final known = passwords?[realm];
    if (known != null) {
      if (await handle.unlock(known)) {
        return;
      }
      // Файл заменили, и пароль у него другой: прежний больше не нужен.
      passwords?.forget(realm);
    }

    if (!mayAsk || credentials == null) {
      throw ViewerRefused(
        credentials == null
            ? said.tr('This PDF is password-protected — open it with the system (Cmd-O)')
            : said.tr('This PDF is password-protected — press F3 to enter the password'),
      );
    }

    var request = CredentialRequest(
      realm: realm,
      title: 'Password-protected PDF',
      message: entry.name,
      retry: known != null,
    );
    while (true) {
      final answer = await credentials.obtain(request);
      // Закрыли окно — передумали: показ не открывается, и говорить не о чем.
      if (answer == null) {
        throw const OperationCanceled();
      }
      await checkpoint();
      final password = answer.password ?? '';
      if (await handle.unlock(password)) {
        passwords?.remember(realm, password);
        return;
      }
      request = request.retrying();
    }
  }
}

/// Пароли, названные в этом сеансе, — по адресу файла.
///
/// Помнит тот, кто спрашивает (`docs/spec/client-server.md`, §7.3): пароль от
/// PDF спрашивает просмотрщик, он и помнит. Только в памяти — на диск пароль
/// не пишется нигде.
class PdfPasswords {
  final Map<String, String> _known = {};

  /// Ключ: схема и путь. Схема — чтобы не спутать с паролем от архива по тому
  /// же пути.
  static String realmOf(FileEntry entry) => 'pdf:${entry.path}';

  String? operator [](String realm) => _known[realm];

  void remember(String realm, String password) => _known[realm] = password;

  void forget(String realm) => _known.remove(realm);
}
