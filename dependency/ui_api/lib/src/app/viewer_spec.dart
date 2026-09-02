import 'package:fc_api/fc_api.dart';

import 'application.dart';
import 'viewport.dart';

/// Где показывают файл.
///
/// Разница не в содержимом, а в раме и в клавишах: во весь экран показ занимает
/// место панелей и забирает ввод сразу, в области панели — стоит рядом со
/// списком и получает ввод, только когда в него вошли.
enum ViewerPlace {
  /// Во весь экран: `F3`.
  fullscreen,

  /// В области соседней панели: быстрый просмотр (`Shift-F3`).
  panel,
}

/// Что показать и куда.
class ViewerRequest {
  const ViewerRequest({
    required this.app,
    required this.entry,
    required this.content,
    required this.place,
    required this.checkpoint,
    this.siblings = const [],
    Content Function(FileEntry entry)? contentOf,
  }) : _contentOf = contentOf;

  /// Приложение: показу бывает нужно спросить у него объявленное другими.
  ///
  /// Сведениям об объекте — провайдеров сведений; будущему показу с
  /// форматтерами (Г3) — форматтеров. Просмотрщик текста и картинок обходятся
  /// без него, и это правильный порядок вещей: даётся, но не требуется.
  final Application app;

  /// Файл, который открывают, — строкой списка.
  final FileEntry entry;

  /// Его содержимое: байты живут за границей и едут потоком
  /// (`docs/spec/client-server.md`, §6.2).
  final Content content;

  final ViewerPlace place;

  /// Соседи по списку — то, что показано в панели рядом.
  ///
  /// Листать альбом стрелками умеет просмотрщик картинок, и берёт он их
  /// отсюда, а не из каталога: список уже на руках, он отсортирован так же,
  /// как видит человек, и лишнего похода за границу не стоит. Пусто —
  /// листать нечем: показ открыли не из панели.
  final List<FileEntry> siblings;

  final Content Function(FileEntry entry)? _contentOf;

  /// Содержимое соседа — чтобы листать, не выходя в панель.
  Content contentFor(FileEntry entry) {
    final read = _contentOf;
    if (read == null || entry.name == this.entry.name) {
      return content;
    }
    return read(entry);
  }

  /// Пауза и отмена: открытие может идти долго — файл читается с сервера или из
  /// архива, — а курсор в быстром просмотре к тому времени уже ушёл дальше.
  final Future<void> Function() checkpoint;
}

/// Показ одного файла: то, что просмотрщик ставит в область.
///
/// Общий предок всем просмотрщикам нужен ради клавиш, которые у них одинаковы:
/// `Esc` и `F10` закрывают показ, чем бы он ни был, и оболочка объявляет это
/// один раз — `KeyBinding.inState<ViewerContent>`. Своё каждый объявляет на
/// свой тип.
abstract interface class ViewerContent implements ViewportState {
  /// Что показано: из строки берутся заголовок и размер.
  FileEntry get entry;

  /// Где показано. Приходит при открытии и не меняется: спросить потом
  /// неоткуда — состояние стоит не в области, а внутри хозяина.
  ViewerPlace get place;
}

/// Просмотрщик не берётся за этот файл — и вот почему.
///
/// Причина сказана человеку, а не в журнал: предел размера у каждого свой, и
/// «не открылось» без объяснения — худший из ответов. Показывает её то место,
/// куда открывали: `F3` — сообщением, быстрый просмотр — словами в панели.
class ViewerRefused implements Exception {
  const ViewerRefused(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// Объявление просмотрщика: чем он берётся и что открывает.
class ViewerSpec {
  const ViewerSpec({
    required this.id,
    required this.title,
    required this.accepts,
    required this.open,
    this.priority = 0,
  });

  /// Устойчивое имя: `text`, `image`. В настройках и в будущем «открыть чем».
  final String id;

  /// Название для человека — «Text», «Image».
  final String title;

  /// Больше — раньше спрашивают. При равном порядок объявления модулей.
  final int priority;

  /// Берётся ли за такую строку.
  ///
  /// [type] — тип по содержимому, когда он будет известен (Б6). Пока его нет,
  /// приходит null, и решать приходится по имени — тем же способом, каким
  /// выбирается провайдер архива.
  final bool Function(FileEntry entry, ContentType? type) accepts;

  /// Открыть: прочитать столько, сколько нужно, и отдать показ.
  ///
  /// Читает сам просмотрщик, а не тот, кто его позвал: тексту нужны строки,
  /// картинке — байты и декодер. Читающий за них неизбежно стал бы `switch` по
  /// видам файлов, а реестр заводится ровно затем, чтобы такого `switch` не
  /// было нигде.
  ///
  /// Отказ — [ViewerRefused]; ошибка чтения — обычное исключение источника.
  final Future<ViewerContent> Function(ViewerRequest request) open;
}

/// Тип содержимого файла — то, что принесёт Б6.
///
/// Заведён сейчас и намеренно пуст: без него `accepts` пришлось бы менять всем
/// просмотрщикам, когда тип появится. Пустой типозаменитель дешевле правки в
/// каждом модуле.
abstract interface class ContentType {
  /// `image/png`, `text/plain`.
  String get mime;
}
