import '../async/async_operation.dart';
import 'fs_node.dart';
import 'node_path.dart';
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

  /// Создаёт источник по адресу.
  ///
  /// Каждый вызов — своё подключение: две панели на одном сервере не делят
  /// состояние, как не делят его и два открытых архива над одним файлом.
  AsyncOperation<TreeProvider> openAddress(Uri address) {
    final factory = _addresses[address.scheme.toLowerCase()];
    if (factory == null) {
      // Имя протокола, а не вся строка: разговор о нём, а не о пути, — и
      // пароль, набранный прямо в адресе, в сообщение не попадает.
      return CompletedOperation.error(FsError(address.scheme, FsErrorKind.unsupportedScheme));
    }
    return factory(address);
  }

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

  /// Монтирует провайдера схемы [scheme] над узлом [host].
  ///
  /// Каждый вызов создаёт нового: узлы дерева живут ровно до перечитывания
  /// каталога, и держать провайдера дольше, чем открыта панель, незачем.
  AsyncOperation<TreeProvider> mount(String scheme, FsNode host) {
    final factory = _factories[scheme];
    if (factory == null) {
      return CompletedOperation.error(FsError(host.pathString, FsErrorKind.notSupported));
    }
    return factory(host);
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
  /// Возвращает null, если узла нет; недоступная схема — это [FsError].
  ///
  /// [reuse] — провайдеры, которые уже смонтированы и работают: монтировать их
  /// заново нельзя. Смонтированный архив — живой объект с открытым файлом,
  /// временной копией и накопленными изменениями; второй экземпляр поверх того
  /// же файла ничего о них не знает, и записанное через один не увидит другой.
  ///
  /// [from] — корень, с которого начинается разбор. У каждой панели он свой:
  /// одна может стоять на локальной ФС, другая — на сервере.
  AsyncOperation<FsNode?> resolvePath(String path, {TreeProvider? from, Iterable<TreeProvider> reuse = const []}) {
    return TaskOperation<FsNode?>((op) async {
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

      // Смонтированное по дороге придётся закрыть, если путь не разберётся:
      // провайдер архива держит открытый файл, и бросить его молча нельзя.
      final mounted = <TreeProvider>[];

      try {
        for (final part in chain.parts.skip(1)) {
          if (node == null) {
            break;
          }
          // Уже работающий провайдер поверх этого же узла — тот самый, что
          // нужен: заводить второй значило бы разойтись с ним состоянием.
          final existing = _reusable(reuse, part.scheme, node);
          if (existing == null) {
            // Веха про звено цепочки: дальше о себе рассказывает сам провайдер,
            // а о том, что звеньев несколько, знает только разбор пути.
            op.message('Reading ${node.name}…');
          }
          final provider = existing ?? await op.delegate<TreeProvider>(mount(part.scheme, node));
          if (existing == null) {
            mounted.add(provider);
          }
          // Проверка нужна и после делегирования: отмена могла прийти в зазор
          // между концом монтирования и продолжением тела, и без неё
          // смонтированное осталось бы держать открытый файл впустую.
          op.checkCanceled();

          node = await op.delegate<FsNode?>(provider.resolvePath(part.path));
          op.checkCanceled();
        }
      } catch (_) {
        await disposeAll(mounted);
        rethrow;
      }

      if (node == null) {
        await disposeAll(mounted);
      }
      return node;
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
  /// обращения.
  AsyncOperation<FsNode?> resolveDisplayPath(
    String path, {
    TreeProvider? from,
    Iterable<TreeProvider> reuse = const [],
  }) {
    final chain = NodePath.parse(path);
    if (chain.parts.length > 1) {
      // Схемы на месте — строка машинная и однозначная, гадать не о чем.
      return resolvePath(path, from: from, reuse: reuse);
    }

    return TaskOperation<FsNode?>((op) async {
      final start = from ?? root;
      final first = chain.parts.first;
      // То же правило, что и в [resolvePath]: чужая схема в начале — это другой
      // корень, и открывает его не разбор пути.
      if (first.scheme != start.scheme && first.scheme != NodePath.defaultScheme) {
        throw FsError(path, FsErrorKind.notSupported);
      }

      // Смонтированное по дороге придётся закрыть, если путь не разберётся.
      final mounted = <TreeProvider>[];
      try {
        final node = await _resolveMounting(start, _expandHome(first.path, start), reuse, mounted, op);
        if (node == null) {
          await disposeAll(mounted);
        }
        return node;
      } on Object {
        await disposeAll(mounted);
        rethrow;
      }
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
  Future<FsNode?> _resolveMounting(
    TreeProvider provider,
    String path,
    Iterable<TreeProvider> reuse,
    List<TreeProvider> mounted,
    TaskOperation<FsNode?> op,
  ) async {
    final whole = await op.delegate(provider.resolvePath(path));
    op.checkCanceled();
    if (whole != null) {
      return whole;
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
        return null;
      }

      // Уже работающий провайдер поверх этого же узла — тот самый, что нужен:
      // второй разошёлся бы с ним состоянием.
      final existing = _reusable(reuse, scheme, host);
      if (existing == null) {
        op.message('Reading ${host.name}…');
      }
      final inner = existing ?? await op.delegate<TreeProvider>(mount(scheme, host));
      if (existing == null) {
        mounted.add(inner);
      }
      // См. [resolvePath]: без этой проверки смонтированное утекает.
      op.checkCanceled();

      // Остаток может содержать ещё один архив — вложенные разбираются тем же
      // способом.
      return _resolveMounting(inner, path.substring(slash), reuse, mounted, op);
    }

    return null;
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

  /// Закрывает провайдеров, которые не понадобились.
  ///
  /// Ошибка закрытия не важна: рассказывать нужно о том, из-за чего не вышло
  /// открыть путь, а не о том, как за этим убирали.
  /// Смонтированный поверх этого узла провайдер с такой же схемой; null — его
  /// ещё нет.
  TreeProvider? _reusable(Iterable<TreeProvider> reuse, String scheme, FsNode host) {
    for (final provider in reuse) {
      final mountedOver = provider.rootDirectory.parent;
      if (provider.scheme == scheme &&
          mountedOver != null &&
          identical(mountedOver.provider, host.provider) &&
          mountedOver.pathString == host.pathString) {
        return provider;
      }
    }
    return null;
  }

  static Future<void> disposeAll(Iterable<TreeProvider> providers) async {
    for (final provider in providers) {
      await disposeProvider(provider);
    }
  }

  /// Закрывает провайдера, если ему есть что закрывать.
  static Future<void> disposeProvider(TreeProvider provider) async {
    if (provider is! ProviderLifecycle) {
      return;
    }
    try {
      await (provider as ProviderLifecycle).dispose();
    } on Object {
      // См. [disposeAll].
    }
  }
}
