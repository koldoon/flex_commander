import 'dart:async';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../async/async_operation.dart';
import '../file_attributes.dart';
import '../file_type.dart';
import '../fs_node.dart';
import '../tree_provider.dart';
import 'zip_index.dart';

/// Провайдер дерева поверх zip-архива, открытого на просмотр.
///
/// Реализует ровно два умения: читать дерево ([TreeProvider]) и отдавать
/// содержимое ([FileContentProvider]). Примитивов изменения нет вовсе —
/// значит `panel.editor` внутри архива пуст, и файловые команды выключаются
/// сами, а копировать **из** архива можно: этим занимается движок переноса,
/// у которого для такой пары есть стратегия «поток».
///
/// Неприятная правда формата: **zip требует произвольного доступа**. Оглавление
/// лежит в конце файла, и прочитать его, не умея прыгать по файлу, нельзя.
/// Поэтому архив открывается только там, где у него есть настоящий путь
/// ([ProviderCapabilities.realFileSystem]); архив внутри архива или на сервере
/// придётся сперва скачать во временный файл — это мост, `docs/providers.md`,
/// 5.7. MC делает ровно то же самое, и это не лень, а свойство формата.
class ZipTreeProvider implements TreeProvider, FileContentProvider, ProviderLifecycle {
  ZipTreeProvider._({required this.archivePath, required FsNode host, required ZipIndex index})
    : _host = host,
      _index = index;

  /// Схема для строк пути: `…/archive.zip:zip:/inner/doc.txt`.
  static const String schemeName = 'zip';

  /// Расширения, которые открываются этим провайдером.
  ///
  /// Список короткий намеренно: `jar`, `apk` и прочие «тоже zip» — это тот же
  /// формат, а вот `docx` открывать как папку пользователю почти никогда
  /// не нужно.
  static const Set<String> extensions = {'zip', 'jar'};

  /// Открывает архив: читает оглавление и строит по нему дерево.
  ///
  /// Фабрика для реестра провайдеров; узел-хозяин запоминается, чтобы корень
  /// архива знал, над чем он смонтирован.
  static Future<TreeProvider> open(FsNode host) async {
    if (!host.provider.capabilities.realFileSystem) {
      // Читать оглавление с конца файла можно только у настоящего файла.
      throw FsError(host.pathString, FsErrorKind.notSupported);
    }

    final path = host.pathString;
    return ZipTreeProvider._(archivePath: path, host: host, index: await readZipIndex(path));
  }

  /// Путь к файлу архива в локальной файловой системе.
  final String archivePath;

  /// Узел, над которым провайдер смонтирован: файл архива в чужом дереве.
  final FsNode _host;

  /// Оглавление архива, прочитанное один раз при открытии.
  final ZipIndex _index;

  /// Открытый файл архива и разобранное по нему оглавление.
  ///
  /// Держатся всё время, пока панель показывает архив: оглавление лежит в конце
  /// файла, и открывать его заново на каждое чтение — это лишний проход по
  /// всему оглавлению. На архиве из 2000 записей так уходило 2.7 мс на файл,
  /// почти всё — на повторное чтение.
  ///
  /// Закрывает их [dispose], и потому провайдер обязан быть
  /// [ProviderLifecycle]: без него дескриптор было бы некому отпустить.
  InputFileStream? _input;
  Archive? _archive;

  /// Провайдер закрыт: узлами его дерева пользоваться уже нельзя.
  bool _disposed = false;

  /// Сколько байт отдавать одним куском: столько же читает `dart:io`, и на
  /// таком куске движок успевает и прогресс посчитать, и отмену заметить.
  static const int _chunk = 64 * 1024;

  @override
  String get scheme => schemeName;

  /// Внутри архива менять нечего, настоящих путей у него нет, а читать с
  /// середины файла он не умеет: содержимое распаковывается целиком.
  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(maxConcurrency: 1);

  @override
  late final DirectoryNode rootDirectory = DirectoryNode(provider: this, name: '/', parent: _host);

  /// Корень архива: другого «дома» у него нет.
  @override
  String get homePath => '/';

  /// Путь внутри архива — всегда с косой чертой, каким бы ни был разделитель
  /// снаружи: так он записан и в самом архиве.
  @override
  String pathOf(FsNode node) {
    final names = visiblePathNodes(node).skip(1).map((child) => child.name);
    return '/${names.join('/')}';
  }

  @override
  AsyncOperation<FsNode?> resolvePath(String path) {
    return TaskOperation<FsNode?>((op) async {
      FsNode node = rootDirectory;
      ZipEntry entry = _index.root;

      for (final name in _segments(path)) {
        final child = entry.children[name];
        if (child == null) {
          return null;
        }
        node = _nodeOf(child, node);
        entry = child;
      }
      return node;
    });
  }

  @override
  AsyncOperation<List<FsNode>> getDirectoryListing(DirectoryNode dir, {bool includeHidden = false}) {
    return TaskOperation<List<FsNode>>((op) async {
      final entry = _entryOf(dir);
      if (entry == null || !entry.isDirectory) {
        throw FsError(dir.pathString, FsErrorKind.notFound);
      }

      final nodes = <FsNode>[
        // «..» из корня архива ведёт наружу — туда, где лежит сам архив.
        if (dir.parentDirectory != null) ParentDirNode(dir),
        for (final child in _childrenOf(entry, includeHidden: includeHidden)) _nodeOf(child, dir),
      ];

      dir.nodes = nodes;
      return nodes;
    });
  }

  @override
  Future<List<FsNode>> listChildren(DirectoryNode dir) async {
    final entry = _entryOf(dir);
    if (entry == null) {
      throw FsError(dir.pathString, FsErrorKind.notFound);
    }
    return [for (final child in _childrenOf(entry, includeHidden: true)) _nodeOf(child, dir)];
  }

  /// Ссылок внутри архива мы не показываем: разрешать нечего.
  @override
  AsyncOperation<FsNode?> resolveLink(LinkNode link) => CompletedOperation<FsNode?>(null);

  @override
  Future<void> countEntries(FsNode node, void Function(int bytes) onEntry) async {
    final entry = _entryOf(node);
    if (entry == null) {
      return;
    }
    _walk(entry, (child) => onEntry(child.isDirectory ? 0 : child.size));
  }

  /// Размер считается по оглавлению: обходить нечего, всё уже прочитано.
  @override
  AsyncOperation<int> calculateSize(List<FsNode> nodes) {
    return TaskOperation<int>((op) async {
      var total = 0;
      for (final node in nodes) {
        op.checkCanceled();
        final entry = _entryOf(node);
        if (entry == null) {
          continue;
        }
        _walk(entry, (child) => total += child.isDirectory ? 0 : child.size);
        op.report(OperationProgress(processed: total, message: node.name));
      }
      return total;
    });
  }

  /// Содержимое файла из архива.
  ///
  /// Запись распаковывается целиком в память, и уже оттуда уходит кусками:
  /// deflate читается только с начала, поэтому ни отдать поток лениво, ни
  /// начать с середины нельзя — об этом и говорит `canSeek: false`. Большая
  /// запись стоит своего размера в памяти; потоковая распаковка — отдельная
  /// работа.
  @override
  Future<Stream<List<int>>> openRead(FsNode node, {int offset = 0}) async {
    final entry = _entryOf(node);
    if (entry == null || entry.isDirectory) {
      throw FsError(node.pathString, FsErrorKind.notFound);
    }

    final bytes = await _readEntry(entry.entryName);
    final start = offset.clamp(0, bytes.length);

    return Stream<List<int>>.fromIterable([
      for (var i = start; i < bytes.length; i += _chunk)
        Uint8List.sublistView(bytes, i, (i + _chunk).clamp(i, bytes.length)),
    ]);
  }

  /// Читает одну запись из открытого архива.
  Future<Uint8List> _readEntry(String name) async {
    final archive = _openArchive();
    final path = '$archivePath:$schemeName:/$name';

    final file = archive.find(name);
    if (file == null) {
      throw FsError(path, FsErrorKind.notFound);
    }

    try {
      // Распакованное отдаётся наружу и в самой записи не остаётся: иначе
      // распаковка архива осела бы в памяти целиком. Именно `writeContent`,
      // а не `readBytes`: он умеет освободить кэш, не трогая сжатые данные,
      // и запись остаётся читаемой снова. `clear()` обнулил бы и их.
      final output = OutputMemoryStream();
      file.writeContent(output);
      return output.getBytes();
    } on ArchiveException catch (error) {
      throw FsError(archivePath, FsErrorKind.io, error);
    }
  }

  /// Открытый архив; открывается при первом чтении и живёт до [dispose].
  ///
  /// Оглавление читается второй раз — первый был при монтировании, ради дерева.
  /// Держать его открытым с самого начала незачем: в архив часто заходят
  /// посмотреть, ничего не читая.
  Archive _openArchive() {
    if (_disposed) {
      throw FsError(archivePath, FsErrorKind.notSupported);
    }

    final opened = _archive;
    if (opened != null) {
      return opened;
    }

    final input = InputFileStream(archivePath);
    try {
      final archive = ZipDecoder().decodeStream(input);
      _input = input;
      _archive = archive;
      return archive;
    } on ArchiveException catch (error) {
      unawaited(input.close());
      throw FsError(archivePath, FsErrorKind.io, error);
    }
  }

  /// Закрывает файл архива. Панель зовёт это, уходя из архива.
  @override
  Future<void> dispose() async {
    _disposed = true;
    final input = _input;
    _archive = null;
    _input = null;
    await input?.close();
  }

  ZipEntry? _entryOf(FsNode node) => _index.at(_segments(pathOf(node)));

  Iterable<ZipEntry> _childrenOf(ZipEntry entry, {required bool includeHidden}) {
    final children = entry.children.values.where((child) => includeHidden || !child.name.startsWith('.')).toList();
    // Порядок оглавления произвольный, а сортировкой заведует панель: отдаём
    // хотя бы устойчивый.
    children.sort((a, b) => a.name.compareTo(b.name));
    return children;
  }

  void _walk(ZipEntry entry, void Function(ZipEntry entry) visit) {
    visit(entry);
    for (final child in entry.children.values) {
      _walk(child, visit);
    }
  }

  /// Путь внутри архива разбирается своими силами: разделитель здесь всегда
  /// косая черта, каким бы ни был он в системе, а `package:path` на своей
  /// платформе разберёт `/docs` как корень с именем.
  List<String> _segments(String path) => path.split('/').where((name) => name.isNotEmpty && name != '.').toList();

  FsNode _nodeOf(ZipEntry entry, FsNode parent) {
    final attributes =
        entry.mode == 0
            ? const FileAttributes.unknown()
            : FileAttributes(
              mode: entry.mode,
              modeString:
                  '${entry.isDirectory ? FileType.directory.attributeChar : FileType.regular.attributeChar}'
                  '${_modeString(entry.mode)}',
            );

    if (entry.isDirectory) {
      return DirectoryNode(
        provider: this,
        name: entry.name,
        parent: parent,
        attributes: attributes,
        modified: entry.modified,
      );
    }
    return FileNode(
      provider: this,
      name: entry.name,
      parent: parent,
      size: entry.size,
      attributes: attributes,
      modified: entry.modified,
      executable: attributes.isExecutable,
    );
  }

  /// «rwxr-xr-x» из режима доступа. `dart:io` умеет это только для своих
  /// объектов, а режим в архиве — обычное число.
  static String _modeString(int mode) {
    const flags = ['r', 'w', 'x'];
    final buffer = StringBuffer();
    for (var bit = 8; bit >= 0; bit--) {
      buffer.write(mode & (1 << bit) != 0 ? flags[2 - bit % 3] : '-');
    }
    return buffer.toString();
  }
}
