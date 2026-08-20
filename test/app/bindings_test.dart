import 'package:fc_api/fc_api.dart';
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
            .where((binding) => '${binding.keys}' == 'Esc' && binding.screen == Screens.files)
            .toList();

    // Порядок задаёт приоритет: пока панель занята, Esc достаётся отмене.
    expect(forEsc.map((binding) => binding.commandId), ['panel.cancel', 'panel.selection.clear']);
  });

  test('Esc чужого экрана панелям не мешает', () {
    // У просмотрщика своя Esc — она действует только в его экране, и потому
    // не встаёт в очередь к панельным.
    final elsewhere = runtime.commands.bindings.where(
      (binding) => '${binding.keys}' == 'Esc' && binding.screen != Screens.files,
    );

    expect(elsewhere.map((binding) => binding.commandId), ['viewer.close']);
  });

  test('переход по набранному символу не перехватывает обычные клавиши', () {
    final bindings = runtime.commands.bindings;
    final anyCharacter = bindings.indexWhere((binding) => binding.keys == KeyCombination.anyCharacter);
    expect(anyCharacter, isNot(-1));

    // Привязка к конкретному символу должна стоять раньше «любого символа»,
    // иначе набор имени перехватил бы её. Клавиши без символа (F5, Tab)
    // могут идти и после: под «любой символ» они не подходят.
    final laterCharacters = bindings.sublist(anyCharacter + 1).where((binding) => binding.keys.isCharacter);
    expect(laterCharacters, isEmpty, reason: 'эти привязки уже не сработают: $laterCharacters');
  });

  test('модуль архива добавил свою схему, а не команду', () {
    // Zip виден приложению только как источник: ни одной команды он не ставит.
    expect(runtime.commands.installed.map((command) => command.id), isNot(contains('zip')));
    expect(runtime.app.left.provider, isNotNull);
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

  test('F9 и F10 пока ни за кем не закреплены', () {
    expect(runtime.commands.commandFor(KeyCombination.parse('F9')), isNull);
    expect(runtime.commands.commandFor(KeyCombination.parse('F10')), isNull);
  });
}
