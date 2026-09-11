import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:path/path.dart' as p;

import 'sftp_api.dart';
import 'sftp_mapping.dart';
import 'ssh_address.dart';
import 'ssh_connection.dart';

/// Дерево на чужой машине по SFTP.
///
/// Первый источник, который сам себе корень: архив — звено пути, а сервер —
/// начало другого пути, и панель встаёт на него целиком. Всё остальное — как
/// у локальной файловой системы: примитивы здесь, обход и прогресс в движке
/// переноса.
///
/// Путей два вида — видимый (`//user@host/srv`, он же уходит в настройки) и
/// путь на сервере (`/srv`). Отдельного «физического» пути, как у локального
/// провайдера, здесь нет и не нужно: ссылки на той стороне разворачивает сам
/// сервер, а удаление и переименование он к последней ссылке в пути не
/// применяет — то есть ровно то поведение, которое нам и нужно.
class SftpTreeProvider
    implements
        TreeProvider,
        NodeEditor,
        LinkEditor,
        FileContentProvider,
        FileContentReceiver,
        WriteAccessCheck,
        NodeAttributesEditor,
        ShellHost,
        ProviderLifecycle {
  SftpTreeProvider({
    required this.target,
    required SftpApi sftp,
    required this.homePath,
    SshConnection? connection,
    ElevatedWrites? Function()? elevation,
    Strings? strings,
  }) : _sftp = sftp,
       _connection = connection,
       _elevation = elevation ?? _noElevation,
       strings = strings ?? StringsRegistry();

  /// Строки на языке человека: вехи чтения видно в строке состояния панели.
  final Strings strings;

  /// Повышать нечем: так собирается провайдер в тестах.
  static ElevatedWrites? _noElevation() => null;

  /// Служба повышения — **способом спросить**: она живёт в ядре и появляется
  /// не раньше провайдера.
  final ElevatedWrites? Function() _elevation;

  /// Схема пути. `sftp` — её же второе имя: модуль объявляет оба.
  static const String schemeName = 'ssh';

  /// Подключается по адресу и отдаёт дерево сервера.
  static Future<TreeProvider> open(
    Uri address, {
    required Credentials credentials,
    String? sshDirectory,
    ElevatedWrites? Function()? elevation,
    Strings? strings,
  }) async {
    final target = SshTarget.parse(address);
    if (target.host.isEmpty || target.user.isEmpty) {
      // Ни хоста, ни имени пользователя взять неоткуда: это не адрес.
      throw FsError(address.toString(), FsErrorKind.invalidAddress);
    }

    final connection = await SshConnection.open(target: target, credentials: credentials, sshDirectory: sshDirectory);

    return SftpTreeProvider(
      target: target,
      sftp: connection.sftp,
      homePath: connection.homePath,
      connection: connection,
      elevation: elevation,
      strings: strings,
    );
  }

  final SshTarget target;
  final SftpApi _sftp;
  final SshConnection? _connection;

  /// Дом пользователя **на сервере**: сюда открывается панель и сюда
  /// разворачивается тильда.
  @override
  final String homePath;

  @override
  String get scheme => schemeName;

  late final DirectoryNode _root = DirectoryNode(provider: this, name: '/');

  @override
  DirectoryNode get rootDirectory => _root;

  /// Переименование внутри сервера мгновенное, чтение с середины файла
  /// настоящее (`read(offset:)` уходит в протокол как есть). Дату копия не
  /// сохраняет: байты приезжают потоком, а времена — нет. Пути отдавать
  /// внешним программам нельзя — машина чужая.
  ///
  /// Одновременных работ — две: чужому серверу десяток параллельных обходов
  /// не нужен, а один сделал бы подсчёт размера заметно медленнее самой
  /// работы.
  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(
    canRename: true,
    canSeek: true,
    preservesModified: false,
    realFileSystem: false,
    // Четыре, а не два: канал у SFTP один, но запросы в нём идут вперемешку, и
    // OpenSSH держит в полёте до шестидесяти четырёх. Четыре — скромно даже для
    // домашнего сервера, а задержку они прячут почти целиком.
    maxConcurrency: 4,
  );

  /// Путь внутри провайдера — с началом адреса, чтобы строка целиком
  /// разбиралась обратно в тот же сервер: `ssh://user@host/srv`.
  @override
  String pathOf(FsNode node) => '${target.authority}${remotePathOf(node)}';

  /// Путь на сервере: то, что уходит в протокол.
  ///
  /// Имя цели ссылки в него не входит — путь показывает, как сюда пришли,
  /// а разворачивает ссылку сервер.
  String remotePathOf(FsNode node) {
    final names = visiblePathNodes(node).map((node) => node.name).where((name) => name != '/');
    return names.isEmpty ? '/' : '/${names.join('/')}';
  }

  @override
  Operation<String, FsNode?> resolvePath() {
    return TaskOperation<String, FsNode?>((op, path) async {
      final normalized = _normalize(target.stripAuthority(path));
      if (normalized == '/') {
        return _root;
      }

      final segments = p.posix.split(normalized).skip(1).toList();
      DirectoryNode parent = _root;

      for (var i = 0; i < segments.length; i++) {
        op.checkCanceled();

        final name = segments[i];
        final childPath = p.posix.join(remotePathOf(parent), name);
        final node = await _nodeAt(childPath, name, parent);
        if (node == null) {
          return null;
        }

        if (i == segments.length - 1) {
          return node;
        }
        if (node is! DirectoryNode) {
          // Промежуточный элемент пути не каталог. Ссылка на каталог годится:
          // разворачиваем и идём дальше, видимый путь по-прежнему через неё.
          if (node is LinkNode && node.isDirectoryLink) {
            final resolvedTarget = await _resolveTarget(node);
            if (resolvedTarget is DirectoryNode) {
              parent = resolvedTarget;
              continue;
            }
          }
          return null;
        }
        parent = node;
      }
      return parent;
    });
  }

  @override
  Operation<ListingParams, List<FsNode>> getDirectoryListing() {
    return TaskOperation<ListingParams, List<FsNode>>((op, params) async {
      final dir = params.dir;
      final includeHidden = params.includeHidden;
      final path = remotePathOf(dir);
      op.report(message: strings.tr('Reading {path}…', args: {'path': pathOf(dir)}));

      final entries = await _sftp.listDirectory(path);
      op.checkCanceled();

      final shown = [
        for (final entry in entries)
          if (includeHidden || !entry.name.startsWith('.')) entry,
      ];
      final nodes = <FsNode>[
        if (dir.parentDirectory != null) ParentDirNode(dir),
        ...await _nodesFrom(shown, path, dir, op),
      ];

      dir.nodes = nodes;
      return nodes;
    });
  }

  @override
  Future<List<FsNode>> listChildren(DirectoryNode dir) async {
    final path = remotePathOf(dir);
    final entries = await _sftp.listDirectory(path);
    return _nodesFrom(entries, path, dir, null);
  }

  /// Узлы каталога — **спрашивая сервер о ссылках разом, а не по очереди**.
  ///
  /// Про каждую ссылку надо спросить дважды: куда она ведёт (`readlink`) и
  /// каталог ли там (`stat`). Пока эти вопросы шли один за другим, каждый
  /// стоил полного оборота до сервера, и каталог со ссылками открывался
  /// неприлично долго: замер на живом сервере дал **81 мс на запрос подряд и
  /// 2,6 мс на запрос разом** — в тридцать раз. `/usr/bin` со ста
  /// пятьюдесятью пятью ссылками открывался девятнадцать секунд
  /// (`docs/spec/ssh-listing-speed.md`).
  ///
  /// Пачками, а не все разом: тысяча одновременных запросов — это не ускорение,
  /// а отказ в обслуживании для чужого сервера. Шестнадцать прячут задержку
  /// почти целиком и остаются вежливыми.
  Future<List<FsNode>> _nodesFrom(
    List<SftpEntry> entries,
    String path,
    DirectoryNode dir,
    TaskOperation<Object?, Object?>? op,
  ) async {
    final nodes = List<FsNode?>.filled(entries.length, null);

    // Обычная запись узлом становится даром — сервера о ней спрашивать нечего.
    // Считать её наравне со ссылками значило бы раскидать ссылки по пачкам по
    // две-три штуки, и пачки снова пошли бы одна за другой: первая попытка
    // так и сделала, выиграв всего вдвое вместо тридцати.
    final links = <int>[];
    for (var i = 0; i < entries.length; i++) {
      if (entries[i].isLink) {
        links.add(i);
      } else {
        nodes[i] = nodeFromEntry(entries[i], dir, this);
      }
    }

    for (var from = 0; from < links.length; from += _linkBatch) {
      op?.checkCanceled();
      final to = (from + _linkBatch).clamp(0, links.length);
      await Future.wait([
        for (var k = from; k < to; k++)
          _nodeFrom(
            entries[links[k]],
            p.posix.join(path, entries[links[k]].name),
            dir,
          ).then((node) => nodes[links[k]] = node),
      ]);
    }
    return [for (final node in nodes) node!];
  }

  /// Сколько вопросов о ссылках держать в полёте разом.
  static const int _linkBatch = 16;

  @override
  Operation<LinkNode, FsNode?> resolveLink() {
    return TaskOperation<LinkNode, FsNode?>((op, link) async {
      final resolved = await _resolveTarget(link);
      op.checkCanceled();
      return resolved;
    });
  }

  @override
  Future<FsNode?> lookup(DirectoryNode parent, String name) =>
      _nodeAt(p.posix.join(remotePathOf(parent), name), name, parent);

  @override
  Future<DirectoryNode> createDirectory(DirectoryNode parent, String name) async {
    if (name.isEmpty || name == '.' || name == '..' || name.contains('/')) {
      throw FsError(name, FsErrorKind.invalidName);
    }

    final path = p.posix.join(remotePathOf(parent), name);
    // Существование проверяется до действия: в третьей версии протокола нет
    // кода «уже существует», сервер отвечает общим отказом — по нему не
    // отличить занятое имя от нехватки прав.
    if (await _sftp.stat(path) != null) {
      throw FsError(path, FsErrorKind.alreadyExists);
    }

    await _sftp.makeDirectory(path);

    final created = await _nodeAt(path, name, parent);
    if (created is! DirectoryNode) {
      throw FsError(path, FsErrorKind.io);
    }
    return created;
  }

  /// Копии средствами сервера у SFTP нет: содержимое всё равно идёт через нас.
  /// false — и движок скопирует потоком, читая и записывая по одному
  /// соединению.
  @override
  Future<bool> copyEntry(
    FsNode node,
    DirectoryNode destination,
    String name, {
    bool Function(int bytes)? onBytes,
  }) async => false;

  @override
  Future<void> createLink(DirectoryNode parent, String name, String reference) =>
      _sftp.createLink(p.posix.join(remotePathOf(parent), name), reference);

  @override
  Future<bool> renameEntry(FsNode node, DirectoryNode destination, String name) async {
    if (!identical(destination.provider, this)) {
      // Другая машина: одним действием туда не переехать.
      return false;
    }

    final from = remotePathOf(node);
    final to = p.posix.join(remotePathOf(destination), name);
    try {
      await _sftp.rename(from, to);
      return true;
    } on FsError catch (error) {
      // Разные файловые системы на самом сервере выглядят как общий отказ —
      // отдельного кода для этого в протоколе нет. Отвечаем «не умею», и
      // движок скопирует объект и удалит исходный. Про права и отсутствие
      // объекта сервер говорит внятно — такое молчать нельзя.
      if (error.kind == FsErrorKind.io) {
        return false;
      }
      rethrow;
    }
  }

  @override
  Future<void> deleteEntry(FsNode node) async {
    final path = remotePathOf(node);
    // Каталог к этому моменту пуст: движок обошёл его сам. Ссылка удаляется
    // как ссылка — последнюю ссылку в пути сервер не разворачивает.
    if (node is DirectoryNode) {
      await _sftp.removeDirectory(path);
    } else {
      await _sftp.removeFile(path);
    }
  }

  /// Удаления поддерева одним действием в протоколе нет: рекурсию ведёт
  /// движок — заодно и показывает ход работы.
  @override
  Future<bool> deleteTree(FsNode node) async => false;

  /// Корзины на сервере нет.
  @override
  Future<bool> trashEntry(FsNode node) async => false;

  @override
  bool isSameEntity(FsNode node, DirectoryNode destination) =>
      p.posix.equals(remotePathOf(node), p.posix.join(remotePathOf(destination), node.name));

  @override
  bool isInsideSource(FsNode node, DirectoryNode destination) => p.posix.isWithin(
    p.posix.normalize(remotePathOf(node)),
    p.posix.normalize(p.posix.join(remotePathOf(destination), node.name)),
  );

  @override
  Future<Stream<List<int>>> openRead(FsNode node, {int offset = 0}) =>
      _sftp.openRead(remotePathOf(node), offset: offset);

  /// [length] серверу не нужен: место под файл SFTP не резервирует.
  @override
  Future<StreamSink<List<int>>> openWrite(DirectoryNode parent, String name, {int? length}) async {
    final path = p.posix.join(remotePathOf(parent), name);
    try {
      return await _sftp.openWrite(path);
    } on FsError catch (refusal) {
      // Отказ приходит **сразу**, а не на закрытии: SFTP открывает файл на той
      // стороне и ждёт ответа. Поэтому пробы, как у локальной ФС, здесь не
      // нужно — довольно поймать отказ.
      final elevation = _elevation();
      if (refusal.kind != FsErrorKind.permissionDenied || elevation == null || !elevation.enabled) {
        rethrow;
      }
      return _elevatedWrite(path, elevation);
    }
  }

  /// Запись через повышение: временный файл кладётся **на сервер**, туда же,
  /// где будет выполняться `sudo`.
  ///
  /// `/tmp`, а не рядом с целью: рядом с целью писать как раз и не дают — с
  /// этого всё и началось.
  Future<StreamSink<List<int>>> _elevatedWrite(String path, ElevatedWrites elevation) async {
    final temporary = p.posix.join('/tmp', 'fc-elevated-${DateTime.now().microsecondsSinceEpoch}');
    return ElevatedSink(
      elevation: elevation,
      host: this,
      target: path,
      temporary: temporary,
      about: ElevationRequest(action: strings.tr('Write'), path: path, where: shellLabel),
      into: await _sftp.openWrite(temporary),
      removeTemporary: () => _sftp.removeFile(temporary),
    );
  }

  // --- атрибуты ---
  //
  // Расширенных атрибутов здесь нет и не будет: в третьей версии протокола их
  // не существует вовсе. Словаря пользователей тоже нет — сервер отдаёт числа,
  // и владелец на той стороне так и показывается числом. Врать про имя хуже.

  @override
  Future<NodeAttributes> readAttributes(FsNode node) async {
    final path = remotePathOf(node);
    // По ссылке идём: `SSH_FXP_SETSTAT` тоже идёт по ней, и показывать одно, а
    // менять другое — худший из возможных ответов.
    final entry = await _sftp.stat(path, followLink: true);
    if (entry == null) {
      throw FsError(path, FsErrorKind.notFound);
    }
    return NodeAttributes(
      mode: entry.mode,
      modeString: entry.mode == 0 ? '' : '${entry.type.attributeChar}${permissionsOf(entry.mode)}',
      uid: entry.uid,
      gid: entry.gid,
      modified: entry.modified,
      accessed: entry.accessed,
      // Умения выводятся из того, что сервер **прислал**, а не из того, что мы
      // о нём думаем. Обе даты и оба числа обязательны потому, что в протоколе
      // они лежат парами: не прислал вторую — менять первую нечем.
      canEditMode: entry.mode != 0,
      canEditTimes: entry.modified != null && entry.accessed != null,
      canEditOwner: entry.uid != null && entry.gid != null,
    );
  }

  @override
  Future<void> setMode(FsNode node, int mode) => _sftp.setStat(remotePathOf(node), mode: mode & 0xFFF);

  @override
  Future<void> setTimes(FsNode node, {DateTime? modified, DateTime? accessed}) async {
    if (modified == null && accessed == null) {
      return;
    }
    if (modified != null && accessed != null) {
      await _sftp.setStat(remotePathOf(node), times: (accessed, modified));
      return;
    }
    // Половину пары протокол не выражает — недостающую приходится приносить
    // прочитанной. Между чтением и записью её мог поменять кто угодно, и это
    // не наш выбор, а плата за третью версию протокола.
    final current = await readAttributes(node);
    if (!current.canEditTimes) {
      throw FsError(remotePathOf(node), FsErrorKind.notSupported);
    }
    await _sftp.setStat(remotePathOf(node), times: (accessed ?? current.accessed!, modified ?? current.modified!));
  }

  @override
  Future<void> setOwner(FsNode node, {int? uid, int? gid}) async {
    if (uid == null && gid == null) {
      return;
    }
    if (uid != null && gid != null) {
      await _sftp.setStat(remotePathOf(node), owner: (uid, gid));
      return;
    }
    final current = await readAttributes(node);
    if (!current.canEditOwner) {
      throw FsError(remotePathOf(node), FsErrorKind.notSupported);
    }
    await _sftp.setStat(remotePathOf(node), owner: (uid ?? current.uid!, gid ?? current.gid!));
  }

  /// Пустят ли записать в этот объект — спрашиваем у сервера, а не гадаем по
  /// правам владельца: ими файл описан, а пишет тот, кем мы вошли.
  @override
  Future<bool> canWriteTo(FsNode node) => _sftp.canWriteTo(remotePathOf(node));

  /// Кому принадлежит оболочка — `user@host` того сервера, где стоит панель.
  ///
  /// Он же приглашение в строке: где выполнится набранное, видно до нажатия, и
  /// `rm` на сервере не спутать с `rm` у себя.
  @override
  String get shellLabel => target.display;

  /// Чем сервер встретит входящего, решает сервер: `$SHELL` там свой, и узнать
  /// его до запуска нечем.
  @override
  String? get shellProgram => null;

  /// Адрес панели оболочке сервера ничего не говорит: у неё есть только путь.
  ///
  /// Ищется, а не отрезается с начала: путь панели несёт ещё и схему
  /// (`ssh://user@host/srv`), а `authority` — только `//user@host`. Отрезанное
  /// с начала не совпало бы никогда, и в `cd` уезжал бы адрес целиком.
  @override
  String shellPath(String panelPath) {
    final at = panelPath.indexOf(target.authority);
    return at < 0 ? panelPath : target.stripAuthority(panelPath.substring(at));
  }

  @override
  Future<PtySession> run(String command, {String? directory, int columns = 80, int rows = 24}) {
    return _openShell(command: commandIn(directory, command), columns: columns, rows: rows);
  }

  /// Команда вместе с каталогом, в котором ей положено выполниться.
  ///
  /// Каталог остаётся **параметром**, а не досылается отдельной строкой: канал
  /// `ssh` начинается в домашнем, и сказать об этом можно только самой
  /// оболочке. Обёрткой, потому что тогда ошибочный `cd` виден сразу — команда
  /// не выполнится молча не там.
  ///
  /// `--` перед путём обязательно: каталог с именем `-rf` иначе стал бы
  /// ключом.
  static String commandIn(String? directory, String command) =>
      directory == null ? command : 'cd -- ${quoteForShell(directory)} && $command';

  @override
  Future<PtySession> shell({String? directory, int columns = 80, int rows = 24}) =>
      _openShell(columns: columns, rows: rows);

  Future<PtySession> _openShell({String? command, required int columns, required int rows}) async {
    final connection = _connection;
    if (connection == null) {
      // Провайдер собран без живого соединения — так бывает только в тестах,
      // где оболочку и не спрашивают.
      throw FsError(target.display, FsErrorKind.notSupported);
    }
    return connection.openShell(command: command, columns: columns, rows: rows);
  }

  /// Путь в кавычках для оболочки той стороны.
  ///
  /// Своя копия, а не заимствование у терминала: правила кавычек — про
  /// оболочку, а модуль ssh о модуле терминала знать не должен.
  ///
  /// Одинарные кавычки не толкуются вовсе — кроме самих себя, и закрыть их
  /// ради одной кавычки приходится по всем правилам: `'\''`.
  static String quoteForShell(String value) => "'${value.replaceAll("'", r"'\''")}'";

  @override
  Future<void> dispose() async {
    final connection = _connection;
    if (connection != null) {
      await connection.close();
    } else {
      await _sftp.close();
    }
  }

  /// Узел по пути; null — по этому пути ничего нет.
  Future<FsNode?> _nodeAt(String path, String name, FsNode parent) async {
    final entry = await _sftp.stat(path);
    if (entry == null) {
      return null;
    }
    return _nodeFrom(
      SftpEntry(
        name: name,
        type: entry.type,
        size: entry.size,
        mode: entry.mode,
        modified: entry.modified,
        accessed: entry.accessed,
      ),
      path,
      parent,
    );
  }

  /// Запись — узлом. Про ссылку спрашивается отдельно: куда она ведёт и что
  /// там лежит.
  ///
  /// Это два лишних обращения к серверу на каждую ссылку в каталоге. Цена
  /// того стоит: без типа цели ссылка на каталог не откроется по Enter и уедет
  /// в конец списка при сортировке «каталоги вперёд».
  Future<FsNode> _nodeFrom(SftpEntry entry, String path, FsNode parent) async {
    if (!entry.isLink) {
      return nodeFromEntry(entry, parent, this);
    }

    // Два вопроса об одной ссылке независимы — и задаются разом: по сети
    // «сначала один, потом другой» стоит двух оборотов вместо одного.
    final answers = await Future.wait([
      _sftp.readLink(path),
      _sftp.stat(path, followLink: true).then<Object?>((value) => value),
    ]);
    final reference = answers[0] as String?;
    final resolvedTarget = answers[1] as SftpEntry?;

    return nodeFromEntry(
      SftpEntry(
        name: entry.name,
        type: entry.type,
        size: entry.size,
        mode: entry.mode,
        modified: entry.modified,
        accessed: entry.accessed,
        linkTarget: reference ?? '',
      ),
      parent,
      this,
      linkTargetType: resolvedTarget?.type,
    );
  }

  /// Разрешает ссылку: цель становится **дочерним узлом самой ссылки**.
  ///
  /// Так дерево помнит, как пользователь сюда попал: переход наверх вернёт в
  /// каталог, где ссылка лежит, а не туда, куда она ведёт. Цепочки
  /// разворачивать не нужно — сервер разворачивает их сам, и закольцованная
  /// ссылка возвращается ошибкой, а не бесконечностью.
  Future<FsNode?> _resolveTarget(LinkNode link) async {
    final path = remotePathOf(link);
    final entry = await _sftp.stat(path, followLink: true);
    if (entry == null) {
      return null;
    }

    final reference = link.reference;
    final resolvedTarget = nodeFromEntry(
      SftpEntry(
        name: reference.isEmpty ? link.name : p.posix.basename(reference),
        type: entry.type,
        size: entry.size,
        mode: entry.mode,
        modified: entry.modified,
        accessed: entry.accessed,
      ),
      link,
      this,
    );

    link.target = resolvedTarget;
    return resolvedTarget;
  }

  /// Путь в канонический вид. Относительный считается от дома пользователя —
  /// так же, как его понял бы сам сервер.
  String _normalize(String path) => p.posix.normalize(path.startsWith('/') ? path : p.posix.join(homePath, path));
}
