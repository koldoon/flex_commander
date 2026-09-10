import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

/// Поля самой модели: имя, путь, тип, размер, даты, права, ссылка, откуда.
///
/// Такой же провайдер, как остальные, и без привилегий: живёт он рядом с окном
/// лишь потому, что описывает не чужое знание, а то, что у узла уже есть.
class BasicsInfoProvider implements NodeInfoProvider {
  const BasicsInfoProvider(this.strings);

  /// Подписи строк — на языке человека: их читают в окне сведений.
  final Strings strings;

  @override
  String get id => 'basics';

  /// Выше всех: это то, зачем окно открывают в первую очередь.
  @override
  int get priority => 1000;

  /// Берётся за всё: у любого узла есть имя и путь.
  @override
  bool accepts(FileEntry entry, ContentType? type) => true;

  @override
  Future<List<NodeInfoSection>> describe(FileEntry entry, NodeSource source) async {
    return [
      NodeInfoSection(title: strings.tr('General'), rows: _general(entry)),
      if (_dates(entry) case final rows when rows.isNotEmpty) NodeInfoSection(title: strings.tr('Dates'), rows: rows),
      if (_access(entry) case final rows when rows.isNotEmpty) NodeInfoSection(title: strings.tr('Access'), rows: rows),
      if (entry.isLink) NodeInfoSection(title: strings.tr('Link'), rows: _link(entry)),
    ];
  }

  List<NodeInfoRow> _general(FileEntry entry) {
    final file = entry.isParent ? null : entry;
    return [
      NodeInfoRow(strings.tr('Name'), entry.name),
      NodeInfoRow(strings.tr('Path'), entry.path),
      NodeInfoRow(strings.tr('Type'), _typeOf(entry)),
      // Спрашивают «что это», а не «как показать»: правило показа с его
      // ограничением длины тут ни при чём.
      if (file != null && extensionOf(entry.name).isNotEmpty)
        NodeInfoRow(strings.tr('Extension'), extensionOf(entry.name)),
      // У каталога размер не пишем вовсе: считать его — обойти дерево, и
      // делать это молча при открытии окна нельзя. Для этого есть кнопка.
      // До последнего байта, а не сокращённо, как в колонке панели: здесь
      // спрашивают «сколько именно».
      if (!entry.isDirectory && entry.size >= 0) NodeInfoRow(strings.tr('Size'), formatBytesExact(entry.size)),
      // Откуда открыт файл: диск, архив, сервер. По схеме источника — того
      // самого провайдера дерева, в котором узел живёт.
      NodeInfoRow(strings.tr('Where'), entry.scheme),
    ];
  }

  /// Даты — только те, что источник и правда сообщил.
  ///
  /// Прочерки вместо неизвестного хуже пустоты: они выглядят так, будто дата
  /// есть и она никакая.
  List<NodeInfoRow> _dates(FileEntry entry) {
    final file = entry.isParent ? null : entry;
    if (file == null) {
      return const [];
    }
    return [
      if (file.modified case final at?) NodeInfoRow(strings.tr('Modified'), _formatDate(at)),
      if (file.created case final at?) NodeInfoRow(strings.tr('Created'), _formatDate(at)),
      if (file.accessed case final at?) NodeInfoRow(strings.tr('Accessed'), _formatDate(at)),
    ];
  }

  List<NodeInfoRow> _access(FileEntry entry) {
    final attributes = entry.isParent ? null : entry.attributes;
    if (attributes == null || attributes.modeString.isEmpty) {
      return const [];
    }
    return [
      NodeInfoRow(strings.tr('Permissions'), attributes.modeString),
      if (attributes.mode != 0) NodeInfoRow(strings.tr('Mode'), attributes.mode.toRadixString(8).padLeft(4, '0')),
    ];
  }

  List<NodeInfoRow> _link(FileEntry entry) => [
    NodeInfoRow(strings.tr('Points to'), entry.reference.isEmpty ? strings.tr('unknown') : entry.reference),
    if (entry.linkToDirectory) NodeInfoRow(strings.tr('Target'), strings.tr('directory')),
  ];

  String _typeOf(FileEntry entry) => switch (entry.kind) {
    EntryKind.parent => strings.tr('Parent directory'),
    EntryKind.directory => strings.tr('Directory'),
    EntryKind.link => entry.linkToDirectory ? strings.tr('Link to a directory') : strings.tr('Link'),
    EntryKind.file => strings.tr('File'),
  };

  /// Дата целиком: в сведениях сокращать её незачем — здесь как раз и смотрят
  /// точное время.
  static String _formatDate(DateTime at) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${at.year}-${two(at.month)}-${two(at.day)} ${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
  }
}
