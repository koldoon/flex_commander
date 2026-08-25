import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'package:fc_api/fc_api.dart';
import 'package:path/path.dart' as p;
import 'zip_encoding.dart';
import 'zip_index.dart';

part 'writable_zip_tree_provider.dart';

/// Запись зашифрована, и имеющийся пароль не подошёл — или его нет вовсе.
class _NeedsPassword implements Exception {
  const _NeedsPassword();
}

/// Провайдер дерева поверх zip-архива, открытого на просмотр.
///
/// Реализует ровно два умения: читать дерево ([TreeProvider]) и отдавать
/// содержимое ([FileContentProvider]). Примитивов изменения нет вовсе —
/// значит `panel.editor` внутри архива пуст, и файловые команды выключаются
/// сами, а копировать **из** архива можно: этим занимается движок переноса,
/// у которого для такой пары есть стратегия «поток».
///
/// Читать умеет любой архив, а писать — только тот, что лежит в настоящей
/// файловой системе: см. [WritableZipTreeProvider].
///
/// Неприятная правда формата: **zip требует произвольного доступа**. Оглавление
/// лежит в конце файла, и прочитать его, не умея прыгать по файлу, нельзя.
/// Поэтому архив открывается только там, где у него есть настоящий путь
/// ([ProviderCapabilities.realFileSystem]); архив внутри архива или на сервере
/// придётся сперва скачать во временный файл — это мост, `docs/providers.md`,
/// 5.7. MC делает ровно то же самое, и это не лень, а свойство формата.
class ZipTreeProvider implements TreeProvider, FileContentProvider, ProviderLifecycle {
  ZipTreeProvider._({
    required this.archivePath,
    required FsNode host,
    required ZipIndex index,
    required this.credentials,
    LocalCopySession? session,
  }) : _host = host,
       _index = index,
       _session = session;

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
  ///
  /// Архив, лежащий не в локальной ФС — внутри другого архива или на сервере, —
  /// сперва оказывается во временном файле: оглавление zip лежит в конце, и
  /// читать его можно только там, где по файлу умеют прыгать. MC делает ровно
  /// то же, и это не лень, а свойство формата. Владеет копией сам провайдер и
  /// убирает её в [dispose].
  static Future<TreeProvider> open(
    FsNode host, {
    required StagingArea staging,
    required Credentials credentials,
    void Function(int bytes)? onBytes,
  }) async {
    final session = LocalCopySession(staging, prefix: 'flex_commander_zip');

    try {
      final path = await session.localPathOf(host, onBytes: onBytes);
      final index = await readZipIndex(path);

      if (session.copied == 0) {
        // Архив лежит в настоящей файловой системе: в него можно и писать.
        // Пересобранный архив заменит этот же файл.
        return WritableZipTreeProvider._(
          archivePath: path,
          host: host,
          index: index,
          credentials: credentials,
          staging: staging,
        );
      }

      // Архив внутри архива или на сервере: открыт через временную копию.
      // Писать в неё бессмысленно — изменения ушли бы вместе с копией, — и
      // потому такой архив остаётся только для чтения.
      return ZipTreeProvider._(archivePath: path, host: host, index: index, credentials: credentials, session: session);
    } on Object {
      // Битый архив или отмена: копия не должна пережить неудачу.
      await session.purge();
      rethrow;
    }
  }

  /// Путь к файлу архива в локальной файловой системе.
  final String archivePath;

  /// Откуда берётся пароль, когда запись зашифрована.
  final Credentials credentials;

  /// Пароль, которым запись расшифровалась; null — архив без пароля.
  ///
  /// Живёт, пока открыт архив: спрашивать на каждую запись значило бы окно на
  /// каждый файл.
  String? _password;

  /// Адрес, под которым помнится пароль к этому архиву.
  static String realmOf(String archivePath) => '$schemeName:$archivePath';

  /// Пароль в том виде, в каком его ждёт библиотека: байтами UTF-8.
  ///
  /// Ключ она выводит из `password.codeUnits`, то есть из кодов UTF-16, — а
  /// архиваторы (`zip`, 7-Zip) берут байты UTF-8. Для латиницы это одно и то
  /// же, а «тайна» даёт другой ключ, и архив не открывается **никогда**, каким
  /// бы верным пароль ни был. Строка из байтов даёт библиотеке ровно то, на что
  /// она рассчитана.
  String? get _passwordForLibrary {
    final password = _password;
    return password == null ? null : String.fromCharCodes(utf8.encode(password));
  }

  /// Узел, над которым провайдер смонтирован: файл архива в чужом дереве.
  final FsNode _host;

  /// Оглавление архива, прочитанное один раз при открытии.
  final ZipIndex _index;

  /// Временная копия архива; null — архив и так лежал в локальной ФС.
  final LocalCopySession? _session;

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
  Operation<String, FsNode?> resolvePath() {
    return TaskOperation<String, FsNode?>((op, path) async {
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
  Operation<ListingParams, List<FsNode>> getDirectoryListing() {
    return TaskOperation<ListingParams, List<FsNode>>((op, params) async {
      final dir = params.dir;
      final includeHidden = params.includeHidden;
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
  Operation<LinkNode, FsNode?> resolveLink() => CompletedOperation<LinkNode, FsNode?>(null);

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
  Operation<List<FsNode>, int> calculateSize() {
    return TaskOperation<List<FsNode>, int>((op, nodes) async {
      var total = 0;
      for (final node in nodes) {
        op.checkCanceled();
        final entry = _entryOf(node);
        if (entry == null) {
          continue;
        }
        _walk(entry, (child) => total += child.isDirectory ? 0 : child.size);
        op.report(itemsTransferred: total, message: node.name);
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

    final bytes = await _readEntry(entry);
    final start = offset.clamp(0, bytes.length);

    return Stream<List<int>>.fromIterable([
      for (var i = start; i < bytes.length; i += _chunk)
        Uint8List.sublistView(bytes, i, (i + _chunk).clamp(i, bytes.length)),
    ]);
  }

  /// Читает одну запись из открытого архива.
  Future<Uint8List> _readEntry(ZipEntry entry) async {
    final name = entry.entryName;
    final path = '$archivePath:$schemeName:/$name';
    var request = CredentialRequest(realm: realmOf(archivePath), title: 'Encrypted archive', message: _host.name);

    while (true) {
      try {
        // Зашифрованную запись без пароля читать бессмысленно: распаковщик
        // подавится ещё зашифрованными байтами, и «Filter error» не отличить
        // от испорченного архива. Признак известен из оглавления — спрашиваем
        // сразу, как это делает 7z.
        if (!entry.encrypted || _password != null) {
          return _decodeEntry(name, path, encrypted: entry.encrypted);
        }
      } on _NeedsPassword {
        // Спросим ниже и попробуем снова.
      }

      if (_password != null) {
        // Этот не подошёл: забыть, иначе следующий вопрос вернёт тот же ответ.
        credentials.forget(request.realm);
        request = request.retrying();
      }

      final password = (await credentials.obtain(request))?.password;
      if (password == null || password.isEmpty) {
        throw FsError(path, FsErrorKind.permissionDenied);
      }
      _password = password;
      // Архив открыт без пароля — с ним его надо открыть заново.
      await _closeArchive();
    }
  }

  /// Одна попытка распаковать запись имеющимся паролем.
  Uint8List _decodeEntry(String name, String path, {required bool encrypted}) {
    final archive = _openArchive();

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
      final bytes = output.getBytes();

      if (!_decoded(file, bytes)) {
        throw const _NeedsPassword();
      }
      return bytes;
    } on _NeedsPassword {
      rethrow;
    } on Object catch (error) {
      // У зашифрованной записи любая беда при распаковке значит одно: ключ не
      // тот. ZipCrypto о неверном пароле не сообщает вовсе — распаковщик
      // давится зашифрованными байтами («Filter error, bad data»), а AES
      // говорит «password error». Гадать по тексту незачем: шифрование мы
      // знаем из оглавления.
      if (encrypted) {
        throw const _NeedsPassword();
      }
      throw FsError(archivePath, FsErrorKind.io, error);
    }
  }

  /// Похоже ли, что запись действительно расшифровалась.
  ///
  /// ZipCrypto иногда распаковывается и с неверным паролем — молча, в мусор.
  /// Ловится это контрольной суммой: у такой записи она настоящая, и на мусоре
  /// не сойдётся. У AES сумма объявлена нулём (так устроен AE-2), и проверять
  /// там нечего — зато оттуда приходит внятная ошибка.
  static bool _decoded(ArchiveFile file, List<int> bytes) {
    final declared = file.crc32;
    return declared == null || declared == 0 || getCrc32(bytes) == declared;
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
      final archive = ZipDecoder().decodeStream(input, password: _passwordForLibrary);
      _input = input;
      _archive = archive;
      return archive;
    } on ArchiveException catch (error) {
      unawaited(input.close());
      throw FsError(archivePath, FsErrorKind.io, error);
    }
  }

  /// Закрывает файл архива и убирает временную копию, если она была.
  /// Панель зовёт это, уходя из архива.
  @override
  Future<void> dispose() async {
    _disposed = true;
    await _closeArchive();
    await _session?.purge();
  }

  /// Отпускает открытый файл архива, оставляя провайдер рабочим.
  ///
  /// Нужно пишущему архиву: подменить файл, пока он открыт, нельзя — на
  /// Windows это прямо запрещено. Следующее чтение откроет его заново.
  Future<void> _closeArchive() async {
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
