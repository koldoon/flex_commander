import 'package:fc_api/fc_api.dart';

import 'file_table.dart';
import 'files_screen.dart';

/// Файловые панели.
///
/// Ядро не знает, чем показывают файлы: оно показывает верхний экран стопки и
/// рисует ряд функциональных кнопок. Этот модуль приносит и сам экран, и
/// таблицу файлов как штатный вид содержимого панели.
///
/// Без него приложение соберётся и запустится — просто выше ряда кнопок будет
/// пусто. Так же честно, как сейчас без корневого провайдера.
class Panels implements FcModule {
  const Panels();

  @override
  String get id => 'fc.panels';

  @override
  String get title => 'File panels';

  @override
  void install(FcRegistry registry) {
    // Таблица файлов — штатный вид содержимого панели. Остальные виды
    // (результаты поиска, дерево) объявляются так же, своими модулями.
    registry.viewport(PanelViewports.files, (context, panel) => FileTable(panel: panel));

    // Экран открывается стартовой командой: во время объявления приложения
    // ещё нет, а к первому кадру экран уже должен стоять.
    registry.startup((context) => _OpenFilesScreen(context.app));
  }
}

/// Ставит панели на экран при запуске.
class _OpenFilesScreen extends AppCommand {
  _OpenFilesScreen(this._app);

  final Application _app;

  @override
  String get id => 'panels.show';

  @override
  String get label => 'Show file panels';

  @override
  String get description => 'Put the file panels on screen';

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute() async => _app.screens.open(const FilesScreen());
}
