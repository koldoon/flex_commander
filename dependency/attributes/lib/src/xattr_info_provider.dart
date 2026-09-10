import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

/// Расширенные атрибуты — разделом в окне сведений.
///
/// Обещание [`file-info.md`](../../../../docs/spec/file-info.md), §4а: правка
/// атрибутов дополняет сведения своим разделом, и окно об этом ничего не знает.
///
/// Живёт здесь, а не в шелле сведений: рассказывает о них тот, кто с ними и
/// работает. Выключили модуль правки — раздел пропал, остальные на месте.
class XattrInfoProvider implements NodeInfoProvider {
  const XattrInfoProvider(this.strings);

  /// Подписи строк — на языке человека: их читают в окне сведений.
  final Strings strings;

  @override
  String get id => 'xattr';

  /// Ниже основных полей и выше того, что читают из содержимого: расширенные
  /// атрибуты — это всё ещё про сам файл, а не про то, что внутри.
  @override
  int get priority => 900;

  /// Берётся за всё, у чего есть путь.
  ///
  /// Спрашивать наперёд, умеет ли источник расширенные атрибуты, нечем: об
  /// этом знает только он сам, и ответ приходит вместе с ними. Не умеет —
  /// [describe] вернёт пустоту, и раздела не будет вовсе.
  @override
  bool accepts(FileEntry entry, ContentType? type) => !entry.isParent;

  @override
  Future<List<NodeInfoSection>> describe(FileEntry entry, NodeSource source) async {
    final attributes = await source.attributes();
    if (attributes.xattrs.isEmpty) {
      // Источник их не знает или у объекта их нет: раздела нет вовсе. Пустой
      // заголовок — обещание, которого не сдержали.
      return const [];
    }
    return [
      NodeInfoSection(
        title: strings.tr('Extended attributes'),
        rows: [for (final one in attributes.xattrs) NodeInfoRow(one.name, _valueOf(one))],
      ),
    ];
  }

  /// Значение строкой: текст как есть, двоичное — счётом байт.
  ///
  /// Двоичное текстом не притворяется и здесь: показать кашу вместо
  /// `com.apple.FinderInfo` хуже, чем сказать, сколько в нём байт.
  String _valueOf(Xattr xattr) => xattr.text ?? strings.plural(xattr.value.length, one: '{n} byte', other: '{n} bytes');
}
