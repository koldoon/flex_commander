import 'package:fc_api/fc_api.dart';

/// Перечитывает **все** панели, показывающие этот каталог.
///
/// Панель, в которой шла работа, — не единственная, кто её видит: вторая может
/// стоять в том же каталоге, и тогда после переименования она показывает
/// прежнее имя, после создания каталога — не показывает нового, а после
/// удаления — то, чего уже нет.
///
/// Сравниваются полные пути, а не панели: одна и та же папка, открытая дважды,
/// — это два разных объекта панели и один каталог на диске.
/// Каталогов бывает два — откуда и куда, — и панель, стоящая в обоих сразу,
/// должна перечитаться **один раз**: чтение каталога не бесплатно, а на сервере
/// и подавно.
Future<void> reloadPanelsAt(Application app, Iterable<String?> paths) async {
  final wanted = {
    for (final path in paths)
      if (path != null) path,
  };
  if (wanted.isEmpty) {
    return;
  }
  for (final position in const [ViewportPosition.left, ViewportPosition.right]) {
    final panel = app.view.panelAt(position);
    final at = panel?.directory?.pathString;
    if (panel != null && at != null && wanted.contains(at)) {
      await panel.reload();
    }
  }
}
