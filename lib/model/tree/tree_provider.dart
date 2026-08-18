import 'dart:async';

import '../async/async_operation.dart';
import 'fs_node.dart';

/// Вид ошибки доступа к дереву.
enum FsErrorKind {
  notFound,
  permissionDenied,
  notADirectory,
  alreadyExists,
  invalidName,
  targetInsideSource,
  notSupported,
  io,
}

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
    FsErrorKind.targetInsideSource => 'Cannot copy a directory into itself: $path',
    FsErrorKind.notSupported => 'Not supported: $path',
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

  /// Суммарный размер объектов вместе с содержимым каталогов.
  ///
  /// Обход каталога долгий, поэтому операция не молчит до конца, а сообщает
  /// промежуточные суммы: в [OperationProgress.processed] идёт то, что уже
  /// насчитано, в `message` — имя объекта, который считают сейчас. Итог —
  /// результат операции.
  ///
  /// Ссылки не разыменовываются: считается сама ссылка, а не то, куда она
  /// ведёт, — иначе одни и те же байты попали бы в сумму дважды.
  AsyncOperation<int> calculateSize(List<FsNode> nodes);
}

/// Изменение дерева — то, чем пользуются команды.
///
/// Операция целиком: обход, конфликты, вопросы и прогресс. Провайдеры этот
/// интерфейс **не реализуют** — его реализует движок переноса
/// (`TreeTransferEngine`), а провайдер даёт ему примитивы ([NodeEditor]).
/// Разделение нужно затем, чтобы перенос между разными источниками (архив →
/// сеть) выполнялся одним и тем же кодом, а не заново в каждом провайдере.
abstract interface class TreeEditor {
  /// Копирует объекты в каталог.
  ///
  /// Существующие объекты не перезаписываются молча: операция спрашивает
  /// ([OperationRequest]), а если спросить некого — пропускает.
  AsyncOperation<void> copy(List<FsNode> nodes, DirectoryNode destination);

  /// Переносит объекты в каталог.
  AsyncOperation<void> move(List<FsNode> nodes, DirectoryNode destination);

  AsyncOperation<void> remove(List<FsNode> nodes, {bool toTrash = true});

  AsyncOperation<DirectoryNode> makeDirectory(DirectoryNode parent, String name);
}

/// Примитивы изменения дерева: один объект, без рекурсии, без вопросов и без
/// прогресса — всё это дело движка переноса.
///
/// Отдельный интерфейс: провайдер может уметь только читать (архив, открытый на
/// просмотр), и панель это проверяет — `provider is NodeEditor`. Возвращаемое
/// значение — обычный `Future`, а не [AsyncOperation]: своя отмена и свой
/// прогресс шагу не нужны, ими владеет операция, которая шаг вызвала.
///
/// Метод, вернувший `false`, говорит «так я не умею»: это не ошибка, а сигнал
/// движку пойти следующей стратегией. Ошибка — это исключение [FsError].
abstract interface class NodeEditor {
  /// Содержимое каталога для обхода движком: со скрытыми объектами, без
  /// псевдоузла «..» и **без записи** в [DirectoryNode.nodes] — обход приёмника
  /// не должен подменять то, что показывает панель.
  Future<List<FsNode>> listChildren(DirectoryNode dir);

  /// Объект с таким именем в каталоге; null — имя свободно.
  Future<FsNode?> lookup(DirectoryNode parent, String name);

  /// Создаёт каталог. Проверка имени — здесь: она платформенная.
  Future<DirectoryNode> createDirectory(DirectoryNode parent, String name);

  /// Копия объекта средствами самого провайдера — файла или ссылки.
  /// Каталоги движок создаёт и обходит сам, чтобы считать прогресс.
  ///
  /// false — провайдер так не умеет: движок пойдёт потоком или через мост.
  Future<bool> copyEntry(FsNode node, DirectoryNode destination, String name);

  /// Переименование — самый быстрый перенос: поддерево уезжает одним действием.
  /// false — так нельзя: другой диск (`EXDEV`), другой провайдер.
  Future<bool> renameEntry(FsNode node, DirectoryNode destination, String name);

  /// Удаляет один объект. Каталог к этому моменту пуст: движок обошёл его сам,
  /// чтобы показать ход работы.
  Future<void> deleteEntry(FsNode node);

  /// Удаляет объект вместе со всем, что под ним, одним действием.
  ///
  /// Движок зовёт это там, где поштучный прогресс не нужен: перезапись
  /// приёмника, уборка источника после копирования. false — провайдер так не
  /// умеет, и движок удалит поддерево обходом.
  Future<bool> deleteTree(FsNode node);

  /// Переносит объект в корзину — тоже одним действием.
  /// false — корзины у провайдера нет.
  Future<bool> trashEntry(FsNode node);

  /// Обходит поддерево [node], сообщая о каждом объекте (включая сам [node])
  /// через [onEntry]: движок считает объекты сам и рисует из них общее число.
  ///
  /// Исключение из [onEntry] наружу не гасится — так движок прекращает подсчёт,
  /// когда работа кончилась раньше него.
  Future<void> countEntries(FsNode node, void Function() onEntry);

  /// Тот же самый объект: класть его туда, где он и лежит, нечего.
  /// Вызывается, только когда источник и приёмник одного провайдера.
  bool isSameEntity(FsNode node, DirectoryNode destination);

  /// Приёмник лежит внутри источника: копирование каталога в самого себя
  /// не закончилось бы никогда. Тоже в пределах одного провайдера.
  bool isInsideSource(FsNode node, DirectoryNode destination);
}

/// Байтовый ввод-вывод: то, из чего движок переноса строит единый цикл
/// копирования — стратегию «поток», работающую из любого источника в любой.
///
/// Отдельный интерфейс, как [NodeEditor], и по той же причине: уметь читать
/// дерево и уметь отдавать содержимое — разные умения. Провайдер поиска отдаёт
/// листинг, но не байты; провайдер только для чтения отдаёт байты, но не
/// принимает их.
///
/// Возвращается поток, а не готовые байты: файл может быть больше памяти, и
/// движку нужно место, где считать прогресс и проверять отмену между кусками.
abstract interface class FileContentProvider {
  /// Содержимое файла потоком.
  ///
  /// [offset] — сколько байт пропустить от начала. Не роскошь: без него не
  /// будет докачки, а на сети она нужна.
  ///
  /// Ошибка чтения приходит ошибкой потока, а не исключением из этого вызова:
  /// открыть файл и читать его — разные моменты времени.
  Future<Stream<List<int>>> openRead(FsNode node, {int offset = 0});

  /// Приёмник для содержимого нового файла.
  ///
  /// [length] — сколько байт будет записано, если это известно заранее: HTTP и
  /// FTP просят размер вперёд, локальной ФС он не нужен.
  Future<StreamSink<List<int>>> openWrite(DirectoryNode parent, String name, {int? length});
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
