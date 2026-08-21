import 'dart:async';

import '../async/async_operation.dart';
import 'fs_node.dart';
import 'node_path.dart';
import 'provider_lease.dart';
import 'tree_provider.dart';

/// Создаёт провайдера поверх узла: архив — над файлом, удалённая ФС — над
/// строкой пути.
///
/// Корень созданного провайдера обязан считать своим родителем [host] — этим
/// монтирование и держится: путь наверх из архива приводит в каталог, где он
/// лежит, а полный путь узла собирается через оба дерева.
///
/// Ошибку сообщает исключением [FsError]: битый архив — это не «пустой архив».
///
/// Операция, а не `Future`: открыть архив бывает долго — лежащий на сервере
/// сперва копируется во временный файл, — и всё это время работа должна
/// рассказывать о себе и прерываться. Оба свойства уже есть у [AsyncOperation],
/// и заводить ради них второй канал незачем.
typedef ProviderFactory = AsyncOperation<TreeProvider> Function(FsNode host);

/// Создаёт источник по адресу: `ssh://user@host/srv` — это подключение.
///
/// В отличие от [ProviderFactory], такому источнику не над чем монтироваться:
/// он сам себе корень. Архив — звено пути (`/home/a.zip:zip:/inner`), сервер —
/// начало другого пути, и это разные вещи, сколько бы общего у них ни было.
///
/// **Пароль в путях созданного источника не появляется.** Из адреса он берётся
/// один раз и уходит в `Credentials`; `pathOf` возвращает `//user@host/…`.
/// Иначе пароль утёк бы в `settings.json` вместе с путём панели. По той же
/// причине его нет и в сообщениях о ходе работы: там только схема и хост.
///
/// Операция, а не `Future`, — по той же причине, что и у [ProviderFactory]:
/// подключение к серверу на другом конце света идёт секундами, и всё это время
/// пользователь вправе знать, чего ждёт, и вправе перестать ждать.
typedef AddressFactory = AsyncOperation<TreeProvider> Function(Uri address);

/// Реестр провайдеров: какая схема чем открывается и что во что вкладывается.
///
/// Вложенность выражена композицией, а не наследованием: провайдер архива
/// ничего не знает о том, над чем он смонтирован, а тот, над кем монтируют, —
/// о существовании архивов. Связывает их только этот реестр.
///
/// Так же устроен MC (`vfs_path_t` — цепочка частей, каждую разбирает свой
/// бэкенд); Total Commander и Far вместо цепочки держат список плагинов и
/// спрашивают каждый, возьмётся ли он за файл.
class ProviderRegistry {
  ProviderRegistry({TreeProvider? root}) : _root = root;

  TreeProvider? _root;

  /// Провайдер, с которого начинается любой путь: обычно локальная ФС.
  ///
  /// Ставится при сборке приложения ([setRoot]), а не задаётся конструктором:
  /// какой источник корневой — решение сборки, и модуль вправе предложить свой.
  TreeProvider get root {
    final root = _root;
    if (root == null) {
      throw StateError('Корневой источник не задан: ProviderRegistry.setRoot до первого обращения');
    }
    return root;
  }

  /// Задан ли корневой источник.
  bool get hasRoot => _root != null;

  /// Ставит корневой источник. Второй вызов заменяет прежний — так тесты и
  /// сборка обходятся одним экземпляром реестра.
  void setRoot(TreeProvider provider) => _root = provider;

  final Map<String, ProviderFactory> _factories = {};

  /// Схема → чем открывается адрес с такой схемой.
  final Map<String, AddressFactory> _addresses = {};

  /// Расширение имени → схема. По нему решается, что делать с файлом, на
  /// котором нажали Enter.
  final Map<String, String> _extensions = {};

  /// Схемы, для которых есть фабрика.
  Iterable<String> get schemes => _factories.keys;

  /// Регистрирует провайдера: как он называется в пути и какие файлы им
  /// открываются.
  void register(String scheme, ProviderFactory factory, {Set<String> extensions = const {}}) {
    _factories[scheme] = factory;
    for (final extension in extensions) {
      _extensions[extension.toLowerCase()] = scheme;
    }
  }

  /// Регистрирует источник, открываемый по адресу: `ssh`, `ftp`, `smb`.
  void registerAddress(String scheme, AddressFactory factory) => _addresses[scheme.toLowerCase()] = factory;

  /// Открывается ли адрес с такой схемой.
  bool knowsAddress(String scheme) => _addresses.containsKey(scheme.toLowerCase());

  /// Схема, которой открывается этот объект; null — открывать его нечем,
  /// и панель отдаст его системе.
  ///
  /// Решает расширение имени, а не содержимое: заглядывать внутрь каждого
  /// файла под курсором было бы слишком дорого. Так же поступают TC и Far.
  String? schemeFor(FsNode node) {
    if (node is! FileNode || node is DirectoryNode) {
      return null;
    }
    return _extensions[node.extension.toLowerCase()];
  }

  // --- Смонтированное и его арендаторы ---
  //
  // Владение выражено состоянием, а не местом в коде: смонтированный провайдер
  // жив, пока его держит хоть одна аренда. Иначе владельцем оказывался «тот,
  // кто открыл», а пользователей у открытого архива больше одного, и уходят
  // они не по очереди.

  /// Что смонтировано сейчас: ключ → запись со счётчиком арендаторов.
  final Map<_MountKey, _MountEntry> _mountTable = {};

  /// Что смонтировано и сколько у чего арендаторов.
  ///
  /// Этим проверяется, что после работы ничего не осталось, и этим же справка
  /// ответит на вопрос «почему архив занят».
  List<MountedProvider> get mounted => [
    for (final entry in _mountTable.values)
      MountedProvider(
        scheme: entry.key.scheme,
        host: entry.key.host,
        tenants: entry.tenants,
        opening: entry.provider == null,
      ),
  ];

  /// Монтирует провайдера схемы [scheme] над узлом [host] — или добавляет
  /// арендатора к уже смонтированному над тем же узлом.
  ///
  /// Операция, а не `Future`: монтирование бывает долгим (архив с сервера
  /// копируется целиком), и всё это время оно рассказывает о себе и
  /// прерывается.
  AsyncOperation<ProviderLease> acquire(String scheme, FsNode host) {
    return TaskOperation<ProviderLease>((op) async => _acquireOver(op, scheme, host));
  }

  /// Аренда провайдера над узлом — внутри чужой операции.
  ///
  /// [milestone] говорится, только если монтировать пришлось на самом деле: у
  /// уже открытого архива ждать нечего, и веха о нём была бы мельканием.
  Future<ProviderLease> _acquireOver(TaskOperation<Object?> op, String scheme, FsNode host, {String? milestone}) {
    final factory = _factories[scheme];
    if (factory == null) {
      throw FsError(host.pathString, FsErrorKind.notSupported);
    }
    // Аренда хозяина держится всё время, пока жив тот, кто над ним стоит:
    // архив внутри архива читает файл внешнего.
    return _acquire(op, _MountKey.over(scheme, host), () => factory(host), host: host.provider, milestone: milestone);
  }

  /// То же для источника по адресу: `ssh://user@host/srv`.
  ///
  /// Ключ — схема и адрес без пароля: один и тот же сервер, набранный с
  /// паролем и без, — это одно подключение, а не два. Разные пользователи
  /// одного сервера — разные, поэтому имя в ключ входит.
  AsyncOperation<ProviderLease> acquireAddress(Uri address) {
    return TaskOperation<ProviderLease>((op) async {
      final scheme = address.scheme.toLowerCase();
      final factory = _addresses[scheme];
      if (factory == null) {
        // Имя протокола, а не вся строка: разговор о нём, а не о пути, — и
        // пароль, набранный прямо в адресе, в сообщение не попадает.
        throw FsError(address.scheme, FsErrorKind.unsupportedScheme);
      }
      return _acquire(op, _MountKey.address(scheme, address), () => factory(address));
    });
  }

  /// Ещё один арендатор уже смонтированного; null — этого провайдера никто не
  /// монтировал (общий корень), и арендовать нечего.
  ///
  /// Нужен там, где провайдер уже на руках, а аренды на него нет: панель,
  /// выходящая из вложенного архива во внешний, отпускает внутреннюю аренду —
  /// и внешний ей всё ещё нужен.
  ProviderLease? leaseOf(TreeProvider provider) {
    for (final entry in _mountTable.values) {
      if (identical(entry.provider, provider)) {
        entry.tenants++;
        return _Lease(this, entry);
      }
    }
    return null;
  }

  /// Закрывает всё, не спрашивая счётчиков. Только выход из приложения: спорить
  /// там не с кем, а открытый файл пережить процесс не должен.
  Future<void> disposeAll() async {
    final entries = _mountTable.values.toList();
    _mountTable.clear();
    for (final entry in entries) {
      final provider = entry.provider;
      if (provider != null) {
        await disposeProvider(provider);
      } else {
        entry.open.cancel();
      }
    }
  }

  Future<ProviderLease> _acquire(
    TaskOperation<Object?> op,
    _MountKey key,
    AsyncOperation<TreeProvider> Function() open, {
    TreeProvider? host,
    String? milestone,
  }) async {
    // Пока прежний экземпляр закрывается, новый не монтируется: иначе умирающий
    // zip подменит файл пересобранным ровно тогда, когда новый его читает.
    for (var closing = _mountTable[key]?.closing; closing != null; closing = _mountTable[key]?.closing) {
      await closing;
    }

    var entry = _mountTable[key];
    if (entry == null) {
      // Веха — только о настоящей работе: уже открытый архив ждать не заставит.
      if (milestone != null) {
        op.message(milestone);
      }
      entry = _mountTable[key] = _MountEntry(key: key, host: host == null ? null : leaseOf(host), open: open());
    }
    return _attach(op, entry);
  }

  /// Ставит арендатора в очередь за монтированием — общим на всех.
  ///
  /// Прогресс идёт наверх, а отмена вниз **не** идёт: один ушедший не вправе
  /// прервать работу, которую ждут остальные. Ушли все — тогда и прервёт, это
  /// делает [_close].
  Future<ProviderLease> _attach(TaskOperation<Object?> op, _MountEntry entry) async {
    entry.tenants++;
    final progress = entry.open.progress.listen(op.report);
    try {
      await entry.opened;
      // Отмена могла прийти в зазор между концом монтирования и продолжением
      // тела: без проверки смонтированное осталось бы висеть впустую.
      op.checkCanceled();
      return _Lease(this, entry);
    } on Object {
      await _detach(entry);
      rethrow;
    } finally {
      unawaited(progress.cancel());
    }
  }

  /// Отпускает одного арендатора. Последний ушедший закрывает провайдера.
  Future<void> _detach(_MountEntry entry) async {
    entry.tenants--;
    if (entry.tenants > 0) {
      return;
    }
    entry.closing = _close(entry);
    await entry.closing;
  }

  Future<void> _close(_MountEntry entry) async {
    final provider = entry.provider;
    if (provider != null) {
      await disposeProvider(provider);
    } else {
      // Ещё открывается, а ждать больше некому — незачем и открывать.
      // Опоздавший провайдер закроет сама фабрика (`keepUnlessCanceled`).
      entry.open.cancel();
    }

    // Запись живёт до конца закрытия: acquire по этому ключу дожидается его и
    // монтирует заново, а не получает умирающий экземпляр.
    _mountTable.remove(entry.key);
    // Внешний отпускается после внутреннего: пока внутренний закрывается, он
    // ещё читает файл внешнего.
    await entry.host?.release();
  }

  /// Фабрике: отдать созданное, только если её не отменили.
  ///
  /// Отмена завершает операцию, но не тело: самое долгое место открытия — это
  /// не сеть, а окно пароля, и пока человек его набирает, прервать успевают
  /// не раз. Тело потом всё равно доработает — архив откроется, сессия
  /// установится, — а отдать результат уже некому. Закрыть его может только
  /// сама фабрика: больше ссылки ни у кого нет.
  ///
  /// ```dart
  /// registry.provider('zip', (host) => TaskOperation((op) {
  ///   op.message('Reading ${host.name}…');
  ///   return ProviderRegistry.keepUnlessCanceled(op, ZipTreeProvider.open(host, …));
  /// }));
  /// ```
  static Future<TreeProvider> keepUnlessCanceled(TaskOperation<TreeProvider> op, Future<TreeProvider> opening) async {
    final provider = await opening;
    if (op.isCanceled) {
      await disposeProvider(provider);
      throw const OperationCanceled();
    }
    return provider;
  }

  /// Разбор строки пути через всю цепочку провайдеров.
  ///
  /// `fs:/home/archive.zip:zip:/inner` — это два разбора и одно монтирование
  /// между ними. Пока цепочка из одной части (обычный путь), всё сводится к
  /// [TreeProvider.resolvePath] корневого провайдера.
  ///
  /// Возвращает узел **вместе с арендой** всего, что смонтировано ради него:
  /// отпустить её обязан тот, кто просил разобрать путь, — иначе архив,
  /// открытый по дороге, останется занятым навсегда. Узла нет —
  /// [ResolvedNode.none], и отпускать нечего; недоступная схема — [FsError].
  ///
  /// [from] — корень, с которого начинается разбор. У каждой панели он свой:
  /// одна может стоять на локальной ФС, другая — на сервере.
  AsyncOperation<ResolvedNode> resolvePath(String path, {TreeProvider? from}) {
    return TaskOperation<ResolvedNode>((op) async {
      final start = from ?? root;
      final chain = NodePath.parse(path);
      // Первая часть адресует корень: `fs` в ней — это «схемы не было вовсе»,
      // её подставляет разбор строки. Чужая схема в начале означает **другой**
      // корень, и открывает его не разбор пути, а тот, кому решать, на чём
      // стоять, — панель (`PanelController.openPath`).
      final first = chain.parts.first;
      if (first.scheme != start.scheme && first.scheme != NodePath.defaultScheme) {
        throw FsError(path, FsErrorKind.notSupported);
      }

      FsNode? node = await op.delegate(start.resolvePath(_expandHome(first.path, start)));
      op.checkCanceled();

      // Аренда самого глубокого звена: она же держит все внешние.
      ProviderLease? lease;
      try {
        for (final part in chain.parts.skip(1)) {
          if (node == null) {
            break;
          }
          // Веха про звено цепочки: дальше о себе рассказывает сам провайдер,
          // а о том, что звеньев несколько, знает только разбор пути.
          final inner = await _acquireOver(op, part.scheme, node, milestone: 'Reading ${node.name}…');
          // Прежняя аренда больше не наша забота: новая держит её сама.
          await lease?.release();
          lease = inner;
          // Проверка нужна и после монтирования: отмена могла прийти в зазор
          // между его концом и продолжением тела.
          op.checkCanceled();

          node = await op.delegate<FsNode?>(inner.provider.resolvePath(part.path));
          op.checkCanceled();
        }
      } on Object {
        await lease?.release();
        rethrow;
      }

      if (node == null) {
        // Смонтированное по дороге держать больше некому.
        await lease?.release();
        return const ResolvedNode.none();
      }
      return ResolvedNode(node, lease);
    });
  }

  /// Разбор строки, которую видит пользователь.
  ///
  /// В показываемом пути схем вложенных провайдеров нет — архив в нём выглядит
  /// каталогом (`/home/a.zip/inner`). Однозначно такая строка не разбирается:
  /// по ней не видно, где кончается файл архива и начинается путь внутри него.
  /// Видно это только источнику — по типу узла, — и потому разбор идёт с
  /// вопросами к нему.
  ///
  /// Нужен там, где строку набирает человек: он набирает то, что ему показали,
  /// а показывают ему [NodePath.displayString]. Машинный путь со схемами
  /// (настройки) разбирается по-прежнему [resolvePath] — без единого лишнего
  /// обращения. Аренда возвращается так же.
  AsyncOperation<ResolvedNode> resolveDisplayPath(String path, {TreeProvider? from}) {
    final chain = NodePath.parse(path);
    if (chain.parts.length > 1) {
      // Схемы на месте — строка машинная и однозначная, гадать не о чем.
      return resolvePath(path, from: from);
    }

    return TaskOperation<ResolvedNode>((op) async {
      final start = from ?? root;
      final first = chain.parts.first;
      // То же правило, что и в [resolvePath]: чужая схема в начале — это другой
      // корень, и открывает его не разбор пути.
      if (first.scheme != start.scheme && first.scheme != NodePath.defaultScheme) {
        throw FsError(path, FsErrorKind.notSupported);
      }

      return _resolveMounting(start, _expandHome(first.path, start), op);
    });
  }

  /// Разбирает путь внутри [provider], монтируя то, что встретится по дороге.
  ///
  /// Сначала — путь целиком: строка без архива разбирается одним обращением,
  /// как и раньше. Если не вышло, ищется граница провайдера, и ищется **с
  /// конца**: первый же ответивший префикс и есть она. С начала пришлось бы
  /// перебирать все звенья до неё, а по сети каждое звено — это обмен.
  ///
  /// Границей считается косая черта, поэтому на Windows, где локальные пути
  /// пишутся через обратную, архив в набранном пути не опознается: там разбор
  /// просто вернёт «не найдено», как и до появления этого метода.
  Future<ResolvedNode> _resolveMounting(TreeProvider provider, String path, TaskOperation<Object?> op) async {
    final whole = await op.delegate(provider.resolvePath(path));
    op.checkCanceled();
    if (whole != null) {
      return ResolvedNode(whole, null);
    }

    for (var slash = path.lastIndexOf('/'); slash > 0; slash = path.lastIndexOf('/', slash - 1)) {
      op.checkCanceled();

      // Перебор префиксов о себе не рассказывает: по сети это десяток зондов
      // в секунду, и веха на каждый была бы мельканием ни о чём.
      final host = await op.delegate(provider.resolvePath(path.substring(0, slash)));
      op.checkCanceled();
      if (host == null) {
        continue;
      }

      final scheme = schemeFor(host);
      if (scheme == null) {
        // Звено разобралось, но открывать его нечем: значит пути правда нет,
        // а не «мы не с той стороны посмотрели».
        return const ResolvedNode.none();
      }

      final lease = await _acquireOver(op, scheme, host, milestone: 'Reading ${host.name}…');
      op.checkCanceled();

      try {
        // Остаток может содержать ещё один архив — вложенные разбираются тем же
        // способом.
        final inner = await _resolveMounting(lease.provider, path.substring(slash), op);
        if (inner.node == null) {
          await lease.release();
          return const ResolvedNode.none();
        }
        if (inner.lease != null) {
          // Внутри смонтировали ещё один: он держит наш, и наша аренда лишняя.
          await lease.release();
          return inner;
        }
        return ResolvedNode(inner.node, lease);
      } on Object {
        await lease.release();
        rethrow;
      }
    }

    return const ResolvedNode.none();
  }

  /// Разворачивает `~` в домашний каталог источника.
  ///
  /// Живёт здесь, а не в каждом провайдере: тильда — это соглашение о **записи**
  /// пути, и одинаково полезно оно и локальной ФС, и серверу, у которого свой
  /// `homePath`. Провайдер отвечает за то, где его дом, а не за то, как о нём
  /// сокращённо пишут.
  ///
  /// Разворачивается только ведущая тильда: `~/Developer` — дом, а `dir/~name`
  /// — обычное имя, каких в файловых системах хватает.
  static String _expandHome(String path, TreeProvider provider) {
    if (path != '~' && !path.startsWith('~/')) {
      return path;
    }
    final home = provider.homePath;
    final rest = path.substring(1);
    if (rest.isEmpty) {
      return home;
    }
    // `/` на стыке не должен удвоиться: дом бывает и корнем.
    return home.endsWith('/') ? '$home${rest.substring(1)}' : '$home$rest';
  }

  /// Закрывает провайдера, если ему есть что закрывать.
  ///
  /// Ошибка закрытия проглатывается: рассказывать нужно о том, что не вышло
  /// сделать, а не о том, как за этим убирали.
  static Future<void> disposeProvider(TreeProvider provider) async {
    if (provider is! ProviderLifecycle) {
      return;
    }
    try {
      await (provider as ProviderLifecycle).dispose();
    } on Object {
      // Закрытие — уборка, и её беды пользователя не касаются.
    }
  }
}

/// Ключ таблицы смонтированного.
///
/// Хозяин — **узел, а не строка**: `/a.zip` на диске и `/a.zip` на сервере —
/// разные архивы, и одинаковая строка их не роднит. Поэтому в ключ входит сам
/// провайдер хозяина, и сравнивается он по тождеству.
class _MountKey {
  _MountKey.over(this.scheme, FsNode host) : hostProvider = host.provider, host = host.pathString;

  /// Источник по адресу сам себе корень: хозяина у него нет, а место занимает
  /// адрес без пароля.
  _MountKey.address(this.scheme, Uri address) : hostProvider = null, host = _addressOf(address);

  final String scheme;
  final TreeProvider? hostProvider;
  final String host;

  /// `user@host:22` — без пароля.
  ///
  /// Пароль не годится ни в ключ, ни в показ: с ним один и тот же сервер,
  /// набранный с паролем и без, оказался бы двумя подключениями, а `mounted`
  /// показал бы пароль в справке.
  static String _addressOf(Uri address) {
    final user = address.userInfo.split(':').first;
    final place = address.hasPort ? '${address.host}:${address.port}' : address.host;
    return user.isEmpty ? place : '$user@$place';
  }

  @override
  bool operator ==(Object other) =>
      other is _MountKey && other.scheme == scheme && identical(other.hostProvider, hostProvider) && other.host == host;

  @override
  int get hashCode => Object.hash(scheme, hostProvider == null ? null : identityHashCode(hostProvider), host);

  @override
  String toString() => '$scheme over $host';
}

/// Запись таблицы: одно смонтированное и все, кто его держит.
class _MountEntry {
  _MountEntry({required this.key, required this.host, required this.open}) {
    opened = open.result.then((value) => provider = value);
    // Ждать монтирования может уже никто — например, его отменили последним
    // ушедшим арендатором. Ошибка при этом обязана считаться прочитанной,
    // иначе Dart сообщит о ней как о непойманной.
    opened.ignore();
  }

  final _MountKey key;

  /// Аренда того, над кем смонтировано; null — сам себе корень (адрес).
  final ProviderLease? host;

  /// Монтирование, общее на всех арендаторов.
  final AsyncOperation<TreeProvider> open;

  late final Future<TreeProvider> opened;

  /// Готовый провайдер; null — ещё открывается или уже не откроется.
  TreeProvider? provider;

  int tenants = 0;

  /// Идущее закрытие; null — не закрывается.
  Future<void>? closing;
}

/// Аренда на руках у одного арендатора.
class _Lease implements ProviderLease {
  _Lease(this._registry, this._entry);

  final ProviderRegistry _registry;
  final _MountEntry _entry;
  bool _released = false;

  @override
  TreeProvider get provider => _entry.provider!;

  @override
  Future<void> release() async {
    // Отпускать полагается из `finally`, куда попадают и по дороге ошибки, и
    // после обычного конца: второй вызов ничего не делает.
    if (_released) {
      return;
    }
    _released = true;
    await _registry._detach(_entry);
  }
}
