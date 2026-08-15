import '../async/async_operation.dart';
import 'fs_node.dart';

/// Вид ошибки доступа к дереву.
enum FsErrorKind { notFound, permissionDenied, notADirectory, alreadyExists, invalidName, io }

/// Ошибка чтения или изменения дерева.
class FsError implements Exception {
  const FsError(this.path, this.kind, [this.cause]);

  final String path;
  final FsErrorKind kind;
  final Object? cause;

  String get message => switch (kind) {
    FsErrorKind.notFound => 'Not found: $path',
    FsErrorKind.permissionDenied => 'Permission denied: $path',
    FsErrorKind.notADirectory => 'Not a directory: $path',
    FsErrorKind.alreadyExists => 'Already exists: $path',
    FsErrorKind.invalidName => 'Invalid name: $path',
    FsErrorKind.io => 'I/O error: $path',
  };

  @override
  String toString() => message;
}

/// Источник дерева узлов: локальная файловая система, архив, удалённая ФС.
///
/// Панель и команды работают только через этот интерфейс, поэтому новый
/// источник данных подключается без изменений в остальном приложении.
abstract interface class TreeProvider {
  /// Схема для строк пути: 'fs', 'zip', 'sftp'.
  String get scheme;

  /// Корневой каталог провайдера.
  DirectoryNode get rootDirectory;

  /// Каталог по умолчанию: сюда открывается панель, если сохранённый путь
  /// недоступен. Для локальной ФС это домашний каталог пользователя.
  String get homePath;

  /// Путь узла внутри этого провайдера, без схемы.
  String pathOf(FsNode node);

  /// Разбор строки пути в узел. Достраивает всю цепочку узлов от корня, чтобы
  /// у панели всегда была рабочая связь `parent` для перехода наверх.
  /// Возвращает null, если узла нет.
  AsyncOperation<FsNode?> resolvePath(String path);

  /// Чтение содержимого каталога. По завершении заполняет [DirectoryNode.nodes].
  AsyncOperation<List<FsNode>> getDirectoryListing(DirectoryNode dir, {bool includeHidden = false});

  /// Разрешение ссылки: заполняет [LinkNode.target].
  AsyncOperation<FsNode?> resolveLink(LinkNode link);
}

/// Изменение дерева.
///
/// Отдельный интерфейс: провайдер может уметь только читать (архив, открытый
/// на просмотр), и команда это проверяет — `provider is TreeEditor`.
abstract interface class TreeEditor {
  TransferOperation copy();

  TransferOperation move();

  AsyncOperation<void> remove(List<FsNode> nodes, {bool toTrash = true});

  AsyncOperation<DirectoryNode> makeDirectory(DirectoryNode parent, String name);
}

/// Пакетная операция переноса узлов между каталогами (возможно, разных
/// провайдеров). Реализуется на этапе файловых операций.
abstract class TransferOperation implements AsyncOperation<void> {
  TransferOperation from(DirectoryNode source);

  TransferOperation to(DirectoryNode destination);

  TransferOperation nodes(List<FsNode> list);

  List<FsNode> get queue;

  int get currentIndex;
}

/// Ссылка на файл локальной ФС — «мост» между разными провайдерами:
/// копирование из архива в удалённую ФС идёт через временные локальные файлы.
class FileReference {
  const FileReference(this.path, this.node);

  final String path;
  final FsNode node;

  @override
  String toString() => path;
}

/// Обмен файлами между провайдерами. Реализуется вместе с [TreeEditor].
abstract interface class FilesProvider {
  AsyncOperation<List<FileReference>> getFiles(List<FsNode> nodes, {bool followLinks = true});

  AsyncOperation<void> putFiles(List<FileReference> files, DirectoryNode toDir);

  AsyncOperation<void> purge();
}
