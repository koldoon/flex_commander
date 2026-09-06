import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import 'find_files_command.dart';
import 'go_to_found_command.dart';
import 'search_query.dart';
import 'search_run.dart';
import 'search_work.dart';

/// Поиск по дереву и работа с найденным.
///
/// Один класс на обе стороны. Обход живёт в ядре, потому что там живут
/// источники: `listChildren` — это поход на диск, в архив или по сети. Наружу
/// находки едут значениями, по ходу дела
/// (`docs/spec/client-server.md`, §5.1.6).
///
/// Быстрый поиск в панели живёт не здесь, а в навигации: он водит курсор по
/// списку, который и так на экране, и общего с обходом дерева у него нет
/// ничего (`spec/file-search.md`, §8).
class FileSearch implements FcBackendModule, FcFrontendModule {
  const FileSearch();

  static const String moduleId = 'fc.search';

  @override
  String get id => 'fc.search';

  @override
  String get title => 'File search';

  @override
  void installBackend(BackendRegistry registry) {
    // Итог работы виден в списке фоновых работ, а пишет его эта сторона.
    registry.strings('ru', _russian);

    registry.operation(SearchWork.kind, (services) => searching(services.resolve<Strings>()));
  }

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.strings('ru', {'File search': 'Поиск файлов'});

    registry.command((context) => FindFilesCommand());
    registry.command((context) => GoToFoundCommand());

    // Привычка Total Commander.
    registry.binding(KeyBinding('Alt-F7', FindFilesCommand.commandId));
    // `Enter` — **раньше** навигации, потому и модуль объявлен раньше неё.
    // Вне списка находок команда невыполнима, и `Enter` открывает объект, как
    // и всегда.
    registry.binding(KeyBinding('Enter', GoToFoundCommand.commandId));
  }

  /// Работа: где искать — единственная цель заявки, о чём — её доводы.
  static Operation<OperationInputs, void> searching([Strings? strings]) {
    return TaskOperation<OperationInputs, void>((op, inputs) async {
      final where = inputs.targets.whereType<DirectoryNode>().firstOrNull;
      if (where == null) {
        // Искать негде: каталог уехал из-под ног, пока окно было открыто.
        throw const FsError('', FsErrorKind.notFound);
      }
      final query = SearchQuery(
        mask: inputs.option<String>(SearchWork.maskOption) ?? '',
        recursive: inputs.option<bool>(SearchWork.recursiveOption) ?? true,
        hidden: inputs.option<bool>(SearchWork.hiddenOption) ?? false,
      );
      await op.delegate(SearchRun.from(where, onFound: inputs.onFound, strings: strings), query);
    });
  }
}

/// Русские строки поиска файлов.
const Map<String, String> _russian = {
  'Content:': 'Содержимое:',
  'Whole words': 'Слова целиком',
  'Regular expression': 'Регулярное выражение',
  'First hit': 'Только первое совпадение',
  'File search': 'Поиск файлов',

  // Команды.
  'Find files': 'Найти файлы',
  'Search the tree below the current directory by name mask': 'Искать по дереву от текущего каталога по маске имени',
  'Go to found file': 'Перейти к найденному',
  'Leave the search results for the directory the file lies in': 'Уйти из находок в каталог, где лежит файл',

  // Окно поиска.
  'Find "{mask}"': 'Поиск «{mask}»',
  'File name:': 'Имя файла:',
  'Start at:': 'Начать с:',
  'Find recursively': 'Искать по всему дереву',
  'Follow symlinks': 'Идти по ссылкам',
  'Using shell patterns': 'Маски как в оболочке',
  'Case sensitive': 'Различать регистр',
  'All charsets': 'Любые кодировки',
  'Skip hidden': 'Пропускать скрытые',
  'Ignore directories:': 'Пропускать каталоги:',
  'Cancel': 'Отмена',

  // Окно находок.
  'Close': 'Закрыть',
  'Again': 'Ещё раз',
  'Background': 'В фон',
  'View · F3': 'Смотреть · F3',
  'Edit · F4': 'Править · F4',
  'Go to file': 'К файлу',
  'To panel': 'В панель',
  'Nothing found': 'Ничего не найдено',
  'Found: {count}': 'Найдено: {count}',
  'Searching…': 'Идёт поиск…',
  'Searching {where}': 'Поиск в {where}',
  'Stopped': 'Прервано',
  'Done': 'Готово',
};
