import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';

/// Сжатый поток как дерево из одной записи.
///
/// `gz` — это сжатие **одного потока**, а не набор файлов: имён внутри нет
/// вовсе. `dump.sql.gz` — это сжатый `dump.sql`, и ничего больше, поэтому
/// провайдер показывает ровно одну запись.
///
/// Отсюда же и `.tar.gz`: внутри него лежит `.tar`, вход в который открывает
/// уже tar-провайдер. Особого случая для двойного расширения писать не
/// приходится — цепочка провайдеров делает это сама.
///
/// **Ничего не распаковывает при открытии и временных файлов не заводит.**
/// Содержимое отдаётся потоком, а разжимает его на диск тот, кому нужен
/// настоящий файл, — обычным `LocalCopySession`. Разжимай провайдер сам, копий
/// было бы две: его собственная и та, что всё равно сделает читающий.
class GzipTreeProvider implements TreeProvider, FileContentProvider {
  GzipTreeProvider._({required FsNode host, required String name, required int size, DateTime? modified})
    : _host = host,
      _name = name,
      _size = size,
      _modified = modified;

  /// Схема для строк пути: `…/dump.sql.gz:gz:/dump.sql`.
  static const String schemeName = 'gz';

  /// Расширения, которые открываются этим провайдером.
  ///
  /// `tgz` — то же самое, записанное короче: имя внутри получается заменой на
  /// `.tar`.
  static const Set<String> extensions = {'gz', 'tgz'};

  /// Открывает поток: узнаёт имя, размер и дату — но не читает содержимое.
  static Future<TreeProvider> open(FsNode host) async {
    return GzipTreeProvider._(
      host: host,
      name: contentNameOf(host.name),
      size: await _sizeOf(host),
      modified: host is FileNode ? host.modified : null,
    );
  }

  /// Имя записи внутри: имя хозяина без `.gz`, а `.tgz` разворачивается в
  /// `.tar` — иначе внутрь него было бы не войти.
  static String contentNameOf(String hostName) {
    final lower = hostName.toLowerCase();
    if (lower.endsWith('.tgz')) {
      return '${hostName.substring(0, hostName.length - 4)}.tar';
    }
    if (lower.endsWith('.gz')) {
      return hostName.substring(0, hostName.length - 3);
    }
    // Имя без расширения вовсе: показывать «то же самое» нельзя — вход в архив
    // стал бы бесконечным.
    return '$hostName.out';
  }

  /// Размер распакованного — из хвоста gzip.
  ///
  /// Последние четыре байта хранят его по модулю 4 ГБ: это единственное место,
  /// где размер известен без распаковки. Читается одним прыжком — если хозяин
  /// умеет прыгать. Не умеет — размер остаётся неизвестным, как у файла на
  /// сервере, который о нём не сказал.
  static Future<int> _sizeOf(FsNode host) async {
    final provider = host.provider;
    if (!provider.capabilities.canSeek || provider is! FileContentProvider || host.size < 4) {
      return FsNode.unknownSize;
    }

    try {
      final tail = <int>[];
      await for (final chunk in await (provider as FileContentProvider).openRead(host, offset: host.size - 4)) {
        tail.addAll(chunk);
      }
      if (tail.length < 4) {
        return FsNode.unknownSize;
      }
      return tail[0] | (tail[1] << 8) | (tail[2] << 16) | (tail[3] << 24);
    } on Object {
      // Размер — украшение: не вышло, значит неизвестен.
      return FsNode.unknownSize;
    }
  }

  final FsNode _host;
  final String _name;
  final int _size;
  final DateTime? _modified;

  @override
  String get scheme => schemeName;

  /// Прыгать по сжатому потоку нельзя: чтобы добраться до конца, надо разжать
  /// всё начало. Об этом честно и говорится — читающий, которому нужны прыжки,
  /// возьмёт локальную копию сам.
  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(maxConcurrency: 1);

  @override
  late final DirectoryNode rootDirectory = DirectoryNode(provider: this, name: '/', parent: _host);

  @override
  String get homePath => '/';

  @override
  String pathOf(FsNode node) {
    final names = visiblePathNodes(node).skip(1).map((child) => child.name);
    return '/${names.join('/')}';
  }

  @override
  Operation<String, FsNode?> resolvePath() {
    return TaskOperation<String, FsNode?>((op, path) async {
      final segments = path.split('/').where((name) => name.isNotEmpty && name != '.').toList();
      if (segments.isEmpty) {
        return rootDirectory;
      }
      return segments.length == 1 && segments.single == _name ? _contentNode() : null;
    });
  }

  @override
  Operation<ListingParams, List<FsNode>> getDirectoryListing() {
    return TaskOperation<ListingParams, List<FsNode>>((op, params) async {
      final dir = params.dir;
      if (dir != rootDirectory) {
        throw FsError(dir.pathString, FsErrorKind.notFound);
      }

      final nodes = <FsNode>[if (dir.parentDirectory != null) ParentDirNode(dir), _contentNode()];
      dir.nodes = nodes;
      return nodes;
    });
  }

  @override
  Future<List<FsNode>> listChildren(DirectoryNode dir) async => [_contentNode()];

  @override
  Operation<LinkNode, FsNode?> resolveLink() => CompletedOperation<LinkNode, FsNode?>(null);

  @override
  Future<void> countEntries(FsNode node, void Function(int bytes) onEntry) async {
    onEntry(_size == FsNode.unknownSize ? 0 : _size);
  }

  @override
  Operation<List<FsNode>, int> calculateSize() {
    return TaskOperation<List<FsNode>, int>((op, nodes) async => _size == FsNode.unknownSize ? 0 : _size);
  }

  /// Содержимое — потоком разжатия поверх байтов хозяина.
  ///
  /// Смещение отрабатывается честно, но дорого: прочитанное до него
  /// выбрасывается, потому что иначе к этому месту не добраться. Об этой цене
  /// и говорит `canSeek: false`.
  @override
  Future<Stream<List<int>>> openRead(FsNode node, {int offset = 0}) async {
    final provider = _host.provider;
    if (provider is! FileContentProvider) {
      throw FsError(node.pathString, FsErrorKind.notSupported);
    }

    final compressed = await (provider as FileContentProvider).openRead(_host);
    final content = gzip.decoder.bind(compressed);
    return offset <= 0 ? content : _skip(content, offset);
  }

  /// Выбрасывает первые [count] байт потока.
  static Stream<List<int>> _skip(Stream<List<int>> source, int count) async* {
    var left = count;
    await for (final chunk in source) {
      if (left <= 0) {
        yield chunk;
        continue;
      }
      if (chunk.length <= left) {
        left -= chunk.length;
        continue;
      }
      yield chunk.sublist(left);
      left = 0;
    }
  }

  /// Единственная запись: имя без `.gz`, размер из хвоста, дата — хозяина.
  ///
  /// Своей даты у сжатого потока может и не быть (её кладут не все
  /// архиваторы), а дата файла есть всегда — и это ровно та дата, которую
  /// человек и ожидает увидеть.
  FsNode _contentNode() =>
      FileNode(provider: this, name: _name, parent: rootDirectory, size: _size, modified: _modified);
}
