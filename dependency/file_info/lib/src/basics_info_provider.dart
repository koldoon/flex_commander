import 'package:fc_api/fc_api.dart';

/// Поля самой модели: имя, путь, тип, размер, даты, права, ссылка, откуда.
///
/// Такой же провайдер, как остальные, и без привилегий: живёт он рядом с окном
/// лишь потому, что описывает не чужое знание, а то, что у узла уже есть.
class BasicsInfoProvider implements NodeInfoProvider {
  const BasicsInfoProvider();

  @override
  String get id => 'basics';

  /// Выше всех: это то, зачем окно открывают в первую очередь.
  @override
  int get priority => 1000;

  /// Берётся за всё: у любого узла есть имя и путь.
  @override
  bool accepts(FsNode node, ContentType? type) => true;

  @override
  Future<List<NodeInfoSection>> describe(FsNode node) async {
    return [
      NodeInfoSection(title: 'General', rows: _general(node)),
      if (_dates(node) case final rows when rows.isNotEmpty) NodeInfoSection(title: 'Dates', rows: rows),
      if (_access(node) case final rows when rows.isNotEmpty) NodeInfoSection(title: 'Access', rows: rows),
      if (node is LinkNode) NodeInfoSection(title: 'Link', rows: _link(node)),
    ];
  }

  List<NodeInfoRow> _general(FsNode node) {
    final file = node is FileNode ? node : null;
    return [
      NodeInfoRow('Name', node.name),
      NodeInfoRow('Path', node.displayPath),
      NodeInfoRow('Type', _typeOf(node)),
      // Спрашивают «что это», а не «как показать»: правило показа с его
      // ограничением длины тут ни при чём.
      if (file != null && extensionOf(node.name).isNotEmpty) NodeInfoRow('Extension', extensionOf(node.name)),
      // У каталога размер не пишем вовсе: считать его — обойти дерево, и
      // делать это молча при открытии окна нельзя. Для этого есть кнопка.
      // До последнего байта, а не сокращённо, как в колонке панели: здесь
      // спрашивают «сколько именно».
      if (node is! DirectoryNode && node.size >= 0) NodeInfoRow('Size', formatBytesExact(node.size)),
      // Откуда открыт файл: диск, архив, сервер. По схеме источника — того
      // самого провайдера дерева, в котором узел живёт.
      NodeInfoRow('Where', node.provider.scheme),
    ];
  }

  /// Даты — только те, что источник и правда сообщил.
  ///
  /// Прочерки вместо неизвестного хуже пустоты: они выглядят так, будто дата
  /// есть и она никакая.
  List<NodeInfoRow> _dates(FsNode node) {
    final file = node is FileNode ? node : null;
    if (file == null) {
      return const [];
    }
    return [
      if (file.modified case final at?) NodeInfoRow('Modified', _formatDate(at)),
      if (file.created case final at?) NodeInfoRow('Created', _formatDate(at)),
      if (file.accessed case final at?) NodeInfoRow('Accessed', _formatDate(at)),
    ];
  }

  List<NodeInfoRow> _access(FsNode node) {
    final file = node is FileNode ? node : null;
    final attributes = file?.attributes;
    if (attributes == null || attributes.modeString.isEmpty) {
      return const [];
    }
    return [
      NodeInfoRow('Permissions', attributes.modeString),
      if (attributes.mode != 0) NodeInfoRow('Mode', attributes.mode.toRadixString(8).padLeft(4, '0')),
    ];
  }

  List<NodeInfoRow> _link(LinkNode node) => [
    NodeInfoRow('Points to', node.reference.isEmpty ? 'unknown' : node.reference),
    if (node.targetType case final type?) NodeInfoRow('Target', type.name),
  ];

  String _typeOf(FsNode node) => switch (node) {
    ParentDirNode() => 'Parent directory',
    DirectoryNode() => 'Directory',
    LinkNode() => node.isDirectoryLink ? 'Link to a directory' : 'Link',
    _ => 'File',
  };

  /// Дата целиком: в сведениях сокращать её незачем — здесь как раз и смотрят
  /// точное время.
  static String _formatDate(DateTime at) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${at.year}-${two(at.month)}-${two(at.day)} ${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
  }
}
