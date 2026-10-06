import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

/// Кто возьмётся показать этот узел; null — никто.
///
/// Спрашивают по убыванию приоритета и останавливаются на первом согласившемся:
/// список ядро уже упорядочило, а решение — здесь, в оболочке. Ядру решать
/// нечем, оно про виды файлов не знает ничего.
///
/// [type] — тип по содержимому, если его успели узнать: имя обманывает, а
/// начало файла нет. Null значит «не знаем» — тогда согласившийся решает по
/// имени, как решал всегда.
ViewerSpec? viewerFor(Application app, FileEntry entry, [ContentType? type]) {
  for (final spec in app.viewers) {
    if (spec.accepts(entry, type)) {
      return spec;
    }
  }
  return null;
}

/// Открыть узел подходящим просмотрщиком.
///
/// Отказ — [ViewerRefused]: и когда никто не взялся, и когда взявшийся не
/// смог. Разница для того, кто открывает, невелика — человеку в обоих случаях
/// нужна причина словами.
Future<ViewerContent> openViewer(
  Application app,
  FileEntry entry,
  Content content,
  ViewerPlace place, {
  Future<void> Function()? checkpoint,
  List<FileEntry> siblings = const [],
  NodeSource Function(FileEntry entry)? sourceOf,
}) async {
  // Тип по содержимому — подсказка, а не условие: он известен, когда строку уже
  // читали ради иконки, и тогда решает он. Ждать его здесь нельзя — показ
  // важнее точности, а чтение бывает долгим.
  final type = app.contentTypes?.known(entry);

  // Спрашивают по очереди: взявшийся вправе сказать «это не моё», прочитав
  // начало файла, — и тогда очередь идёт дальше. По имени решить можно не
  // всегда: текст с незнакомым расширением от двоичного отличается началом
  // (`docs/spec/content-types.md`).
  final request = ViewerRequest(
    app: app,
    entry: entry,
    content: content,
    place: place,
    checkpoint: checkpoint ?? _never,
    siblings: siblings,
    sourceOf: sourceOf,
  );

  for (final spec in app.viewers) {
    if (!spec.accepts(entry, type)) {
      continue;
    }
    try {
      return await spec.open(request);
    } on ViewerDeclined {
      // Ошибся, взявшись: спрашиваем следующего. Человеку об этом знать
      // незачем — он увидит того, кто справился.
      continue;
    }
  }
  throw ViewerRefused(app.strings.tr('Nothing here can show this file'));
}

Future<void> _never() async {}
