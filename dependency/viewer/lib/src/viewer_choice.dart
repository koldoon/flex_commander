import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

/// Кто возьмётся показать этот узел; null — никто.
///
/// Спрашивают по убыванию приоритета и останавливаются на первом согласившемся:
/// список ядро уже упорядочило, а решение — здесь, в оболочке. Ядру решать
/// нечем, оно про виды файлов не знает ничего.
ViewerSpec? viewerFor(Application app, FileEntry entry) {
  for (final spec in app.viewers) {
    // Тип по содержимому появится в Б6; пока его нет, `accepts` решает по
    // имени — тем же способом, каким выбирается провайдер архива.
    if (spec.accepts(entry, null)) {
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
  final spec = viewerFor(app, entry);
  if (spec == null) {
    throw ViewerRefused(app.strings.tr('Nothing here can show this file'));
  }
  return spec.open(
    ViewerRequest(
      app: app,
      entry: entry,
      content: content,
      place: place,
      checkpoint: checkpoint ?? _never,
      siblings: siblings,
      sourceOf: sourceOf,
    ),
  );
}

Future<void> _never() async {}
