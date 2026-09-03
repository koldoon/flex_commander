import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Привязки клавиш собираются из модулей, и порядок модулей задаёт приоритет.
///
/// Проверяется собранное приложение целиком: пока набор команд лежал в одном
/// списке, за этим следил сам список, — теперь следить нужно за сборкой.
void main() {
  late AppRuntime runtime;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    final provider = InMemoryTreeProvider([FakeEntry.directory('/home'), FakeEntry.file('/home/notes.txt', size: 10)]);

    // Приложение собирается тем же списком модулей, что и в настоящем запуске:
    // проверять привязки на другом наборе бессмысленно.
    runtime = await testApp(provider: provider, modules: featureModules());
  });

  // Приложение и временный каталог закрывает сам testApp.
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('каждая привязка указывает на установленную команду', () {
    final ids = runtime.commands.installed.map((command) => command.id).toSet();

    for (final binding in runtime.commands.bindings) {
      expect(ids, contains(binding.commandId), reason: 'привязка $binding указывает в пустоту');
    }
  });

  test('Esc сперва отменяет операцию, а уже потом снимает пометку', () {
    final forEsc =
        runtime.commands.bindings
            .where((binding) => '${binding.keys}' == 'Esc' && (binding.inContent?.call(runtime.app.left) ?? false))
            .toList();

    // Порядок задаёт приоритет. Первой стоит уборка в командной строке — но
    // она невыполнима, пока строка пуста, пока выключен режим `mc` и пока
    // панель занята: отмена работы важнее уборки, и это условие записано в
    // самой команде, а не в порядке.
    //
    // Выход из быстрого поиска стоит перед отменой работы: пока набирают имя,
    // `Esc` принадлежит набору, а невыполним он ровно тогда, когда режим
    // выключен, — и тогда всё идёт как прежде.
    expect(forEsc.map((binding) => binding.commandId), [
      'terminal.clearLine',
      'panel.quickSearch.stop',
      'panel.cancel',
      'panel.selection.clear',
    ]);
  });

  test('Esc чужого содержимого панелям не мешает', () {
    // У просмотрщика своя Esc — она действует только при его содержимом, и
    // потому не встаёт в очередь к панельным.
    final elsewhere = runtime.commands.bindings.where(
      (binding) => '${binding.keys}' == 'Esc' && !((binding.inContent?.call(runtime.app.left) ?? false)),
    );

    // Терминал добавил две: `Esc` в командной строке возвращает ввод панели, а
    // в экране отработавшей команды убирает его. Обе — при своём содержимом, и
    // в очередь к панельным тоже не встают.
    // Терминал объявлен раньше просмотрщика и редактора — он перехватывает
    // печать в режиме `mc`, а выигрывает та привязка, что объявлена раньше.
    // Оболочка просмотра объявила `Esc` дважды: для показа, чем бы он ни был,
    // и отдельно для хозяина быстрого просмотра — показывать тому бывает
    // нечего (под курсором каталог), а уйти оттуда всё равно нужно.
    expect(elsewhere.map((binding) => binding.commandId), [
      'terminal.leaveLine',
      'terminal.closeRun',
      'viewer.close',
      'viewer.close',
      'editor.close',
    ]);
  });

  test('переход по набранному символу не перехватывает обычные клавиши', () {
    final bindings = runtime.commands.bindings;
    // «Любой символ» объявлен дважды. Первым — печать в командную строку
    // (режим `mc`): она невыполнима, пока режим выключен, и тогда клавиша
    // достаётся тому, кто объявлен следом, — в том числе пометке по маске на
    // `+` и `-`. Вторым — переход к имени: он исполним всегда, и вот после
    // него привязке к символу делать уже нечего.
    final anyCharacter = bindings.lastIndexWhere((binding) => binding.keys == KeyCombination.anyCharacter);
    expect(anyCharacter, isNot(-1));
    expect(bindings[anyCharacter].commandId, 'panel.goToName');

    // Привязка к конкретному символу должна стоять раньше «любого символа»,
    // иначе набор имени перехватил бы её. Клавиши без символа (F5, Tab)
    // могут идти и после: под «любой символ» они не подходят.
    //
    // Считаются только **панельные** привязки: «любой символ» объявлен для
    // панелей, и у чужого содержимого он не спорит ни с чем. Масштаб картинки
    // висит на `+` и `-` — и работает, потому что показана картинка, а не
    // список файлов.
    final laterCharacters = bindings
        .sublist(anyCharacter + 1)
        .where((binding) => binding.keys.isCharacter && (binding.inContent?.call(runtime.app.left) ?? true));
    expect(laterCharacters, isEmpty, reason: 'эти привязки уже не сработают: $laterCharacters');
  });

  test('модуль архива добавил свою схему, а не команду', () {
    // Zip виден приложению только как источник: ни одной команды он не ставит.
    expect(runtime.commands.installed.map((command) => command.id), isNot(contains('zip')));
    expect(runtime.app.leftSession.provider, isNotNull);
  });

  test('упаковка разведена по клавишам: zip на Shift-F5, 7z на Shift-F7', () {
    // Два архиватора — две команды: реестр берёт первую подходящую привязку, и
    // на одной клавише вторая никогда бы не сработала.
    expect(runtime.commands.commandFor(KeyCombination.parse('Shift-F5'))?.id, 'zip.create');
    expect(runtime.commands.commandFor(KeyCombination.parse('Shift-F7'))?.id, '7z.create');
    expect(runtime.commands.commandFor(KeyCombination.parse('F7'))?.id, 'file.mkdir');
  });

  test('модуль 7z встаёт и там, где программы нет', () {
    // Внешнего инструмента в тестах не установлено, и это не должно мешать
    // сборке приложения: приложение здесь уже собрано со всеми модулями, а
    // нехватка программы всплывёт при обращении к архиву — понятной ошибкой.
    expect(runtime.modules.map((module) => module.id), contains('fc.7z_archiver'));
  });

  test('у каждой команды есть название для списка команд', () {
    for (final command in runtime.commands.installed) {
      expect(command.label, isNotEmpty, reason: 'у ${command.id} нет названия');
    }
  });

  test('у команд нет одинаковых идентификаторов', () {
    // Модули складываются в один набор, и столкновение имён здесь — не
    // теоретическая возможность, а вопрос времени.
    final ids = runtime.commands.installed.map((command) => command.id).toList();

    expect(ids.toSet(), hasLength(ids.length));
  });

  test('F9 открывает настройки — там, где в mc меню', () {
    expect(runtime.commands.commandFor(KeyCombination.parse('F9'))?.id, 'app.settings');
  });

  test('F10 пока ни за кем не закреплён', () {
    expect(runtime.commands.commandFor(KeyCombination.parse('F10')), isNull);
  });
}
