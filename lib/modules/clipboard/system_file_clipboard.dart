import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/services.dart';

/// Файлы в буфере обмена системы (`docs/spec/file-clipboard.md`).
///
/// Модуль приложения, а не пакета: он разговаривает с раннером — как
/// перетаскивание, и по той же причине.
class FileClipboardModule implements FcFrontendModule {
  const FileClipboardModule();

  @override
  String get id => 'fc.clipboard';

  @override
  String get title => 'File clipboard';

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.strings('ru', {'File clipboard': 'Буфер обмена файлов'});
    registry.service<FileClipboard>((services) => SystemFileClipboard());
  }
}

/// Буфер обмена системы: файлы туда и обратно.
///
/// **Намерение перенести живёт здесь**, а не в буфере: системный буфер его не
/// несёт вовсе. Держится оно рядом с номером записи (`changeCount`), к которой
/// относится: написал в буфер кто-то другой — номер другой, и намерение
/// забыто (§5).
class SystemFileClipboard implements FileClipboard {
  SystemFileClipboard({MethodChannel? channel}) : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'flex_commander/clipboard';

  final MethodChannel _channel;

  /// Что положили **мы** — адресами приложения: у объекта внутри архива и на
  /// сервере другого адреса нет.
  List<String>? _ours;
  bool _move = false;

  /// Номер записи, которой принадлежит [_ours].
  int _change = -1;

  @override
  Future<void> writeFiles(List<FileEntry> entries, {required bool move}) async {
    final addresses = [for (final entry in entries) entry.path];
    // Наружу уходит настоящий путь — он есть только у настоящей файловой
    // системы. У кого его нет, тот уходит текстом: в Finder такое не вставить,
    // а в терминал и в письмо — вполне (§6).
    final real = [
      for (final entry in entries)
        if (entry.realPath.isNotEmpty) entry.realPath,
    ];
    final change = await _channel.invokeMethod<int>('write', {
      'paths': real,
      'text': real.length == entries.length ? null : addresses.join('\n'),
    });

    _ours = addresses;
    _move = move;
    _change = change ?? -1;
  }

  @override
  Future<ClipboardFiles?> readFiles() async {
    final reply = await _channel.invokeMapMethod<String, Object?>('read');
    final change = reply?['change'] as int? ?? -1;

    // Наш буфер — тот, номер записи которого мы и запомнили. Тогда вставляем
    // по своим адресам: `ssh://…` и пути внутри архива система не знает.
    if (_ours case final ours? when change == _change) {
      return ClipboardFiles(addresses: ours, move: _move, ours: true);
    }

    final paths = (reply?['paths'] as List?)?.cast<String>() ?? const <String>[];
    return paths.isEmpty ? null : ClipboardFiles(addresses: paths);
  }
}
