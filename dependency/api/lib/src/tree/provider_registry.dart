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
typedef ProviderFactory = Future<TreeProvider> Function(FsNode host);

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
  Future<TreeProvider> mount(String scheme, FsNode host) async {
    final factory = _factories[scheme];
    if (factory == null) {
      throw FsError(host.pathString, FsErrorKind.notSupported);
    }
    return factory(host);
  }

  /// Разбор строки пути через всю цепочку провайдеров.
  ///
  /// `fs:/home/archive.zip:zip:/inner` — это два разбора и одно монтирование
  /// между ними. Пока цепочка из одной части (обычный путь), всё сводится к
  /// [TreeProvider.resolvePath] корневого провайдера.
  ///
  /// Возвращает null, если узла нет; недоступная схема — это [FsError].
  AsyncOperation<FsNode?> resolvePath(String path) {
    return TaskOperation<FsNode?>((op) async {
      final chain = NodePath.parse(path);
      // Первая часть всегда адресует корневой провайдер: другого корня пока не
      // бывает, а `fs` в ней — это «схемы не было вовсе», её подставляет разбор
      // строки. Чужая схема в начале — отказ до тех пор, пока корневых
      // провайдеров не станет несколько (docs/providers.md, 5.6).
      final first = chain.parts.first;
      if (first.scheme != root.scheme && first.scheme != NodePath.defaultScheme) {
        throw FsError(path, FsErrorKind.notSupported);
      }

      FsNode? node = await root.resolvePath(first.path).result;
      op.checkCanceled();

      // Смонтированное по дороге придётся закрыть, если путь не разберётся:
      // провайдер архива держит открытый файл, и бросить его молча нельзя.
      final mounted = <TreeProvider>[];

      try {
        for (final part in chain.parts.skip(1)) {
          if (node == null) {
            break;
          }
          final provider = await mount(part.scheme, node);
          mounted.add(provider);
          op.checkCanceled();

          node = await provider.resolvePath(part.path).result;
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

  /// Закрывает провайдеров, которые не понадобились.
  ///
  /// Ошибка закрытия не важна: рассказывать нужно о том, из-за чего не вышло
  /// открыть путь, а не о том, как за этим убирали.
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
