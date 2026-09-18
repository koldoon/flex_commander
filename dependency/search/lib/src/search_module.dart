import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import 'find_files_command.dart';
import 'go_to_found_command.dart';
import 'search_address.dart';
import 'search_provider.dart';
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
    registry.strings('ru', {'Found: {count}': 'Найдено: {count}', 'Find {what}': 'Поиск {what}'});

    registry.operation(SearchWork.kind, (services) => searching(services.resolve<Strings>()));

    // Поиск — источник по адресу, как `ssh` и `zip`: весь запрос лежит в
    // строке, и по ней же он восстанавливается (`docs/spec/file-search.md`,
    // §4.1). Обход при монтировании не начинается — источник только называет
    // работу, которой наполняется, а заводит её тот, кто его открыл (§4.2).
    registry.addressProvider(
      SearchAddress.scheme,
      // Ходить ради него никуда не надо: источник монтируется пустым, а обход
      // заводит тот, кто его открыл. Потому и при запуске он восстанавливается
      // как обычный путь (`docs/spec/file-search.md`, §4.6).
      needsConnection: false,
      () => TaskOperation<Uri, TreeProvider>((op, uri) async {
        final address = SearchAddress.of(uri);
        if (address == null) {
          throw FsError(uri.toString(), FsErrorKind.invalidAddress);
        }
        final strings = registry.services.resolve<Strings>();
        // Тем же словом, что и полоска работы: список и работа — одно и то же,
        // и звать их по-разному незачем. «Found:» не годится — так начинается
        // счётчик находок в окне, и два разных смысла читались бы как один.
        return SearchProvider(address, title: strings.tr('Find {what}', args: {'what': address.what}));
      }),
    );
  }

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.strings('ru', _russian);

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
        regexp: inputs.option<bool>(SearchWork.regexpOption) ?? false,
        caseSensitive: inputs.option<bool>(SearchWork.caseOption) ?? false,
        recursive: inputs.option<bool>(SearchWork.recursiveOption) ?? true,
        hidden: inputs.option<bool>(SearchWork.hiddenOption) ?? false,
        ignore: inputs.option<String>(SearchWork.ignoreOption) ?? '',
        followLinks: inputs.option<bool>(SearchWork.followLinksOption) ?? false,
        sizeFrom: inputs.option<int>(SearchWork.sizeFromOption),
        sizeTo: inputs.option<int>(SearchWork.sizeToOption),
        // Через границу время едет числом: `DateTime` значением протокола не
        // является.
        changedAfter: _timeOf(inputs.option<int>(SearchWork.changedAfterOption)),
        changedBefore: _timeOf(inputs.option<int>(SearchWork.changedBeforeOption)),
        content: inputs.option<String>(SearchWork.contentOption) ?? '',
        contentRegexp: inputs.option<bool>(SearchWork.contentRegexpOption) ?? false,
        contentCase: inputs.option<bool>(SearchWork.contentCaseOption) ?? false,
        wholeWords: inputs.option<bool>(SearchWork.wholeWordsOption) ?? false,
        allCharsets: inputs.option<bool>(SearchWork.allCharsetsOption) ?? false,
      );
      // Находки складываются **прямо в источник**, если он назван приёмником:
      // список принадлежит ему, и копить их где-то ещё значило бы завести
      // второго владельца — ровно того, из-за которого прежняя сборка и
      // разъезжалась (`docs/spec/file-search.md`, §4.7).
      final into = inputs.destination?.provider;
      final list = into is SearchProvider ? into : null;
      list?.markFilled();
      void found(List<FsNode> nodes) {
        list?.add(nodes);
        inputs.onFound(nodes);
      }

      await op.delegate(SearchRun.from(where, onFound: found, strings: strings), query);
    });
  }

  static DateTime? _timeOf(int? epochMilliseconds) =>
      epochMilliseconds == null ? null : DateTime.fromMillisecondsSinceEpoch(epochMilliseconds);
}

/// Русские строки поиска файлов.
const Map<String, String> _russian = {
  'Content:': 'Содержимое:',
  'Whole words': 'Слова целиком',
  'Regular expression': 'Регулярное выражение',
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
  'Case sensitive': 'Различать регистр',
  // Остался у поиска по содержимому (Д3): там кодировки и правда бывают
  // разные. В поиске по имени флага больше нет — имена всегда UTF-8.
  'All charsets': 'Любые кодировки',
  'Read as a regular expression': 'Читать как регулярное выражение',
  'The expression is not understood': 'Выражение не разобрано',
  'Size from:': 'Размер от:',
  'to:': 'до:',
  'Changed after:': 'Изменён после:',
  'before:': 'до:',
  'Skip hidden': 'Пропускать скрытые',
  'Ignore directories:': 'Пропускать каталоги:',
  'Cancel': 'Отмена',
  'OK': 'ОК',

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
