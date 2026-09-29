import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flex_commander/bootstrap/frontend_registrations.dart';
import 'package:flex_commander/bootstrap/registrations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Модуль, объявляющий форматтер.
class _FormatterModule implements FcFrontendModule {
  const _FormatterModule(this.formatterId, {this.priority = 0, this.extension = '.json'});

  final String formatterId;
  final int priority;
  final String extension;

  /// Своё имя у каждого: `installAll` пропускает модуль с уже занятым
  /// идентификатором (`registrations.dart:90`), и два одноимённых модуля
  /// проверяли бы не реестр форматтеров, а его.
  @override
  String get id => 'test.formatter.$formatterId.$extension';

  @override
  String get title => 'Formatter $formatterId';

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.formatter(
      FormatterSpec(
        id: formatterId,
        title: 'Formatter $formatterId',
        priority: priority,
        accepts: (entry, type) => entry.name.endsWith(extension),
        format: (text) => text.trim(),
      ),
    );
  }
}

FrontendRegistrations _install(List<FcFrontendModule> modules) =>
    FrontendRegistrations(LazyServices())..installAll(modules);

FileEntry _file(String name) => FileEntry(name: name, kind: EntryKind.file, path: '/home/$name', size: 1);

/// Реестр форматтеров: складывает и упорядочивает — и только.
///
/// Решать, чей это файл, ядру нечем; `accepts` спрашивают показ текста и
/// редактор (`docs/spec/formatters.md`, §2).
void main() {
  test('никто не объявил — реестр пуст, и это законный вид приложения', () {
    // Пусто означает «файл открывается текстом, как раньше», а не «показ
    // сломан».
    expect(_install([]).formatters, isEmpty);
  });

  test('объявленное складывается', () {
    final declared = _install([const _FormatterModule('json')]).formatters;

    expect(declared, hasLength(1));
    expect(declared.single.id, 'json');
    expect(declared.single.accepts(_file('a.json'), null), isTrue);
    expect(declared.single.accepts(_file('a.dart'), null), isFalse);
  });

  test('форматирует то, что дали, и ничего больше не знает', () {
    // Чистая функция текста: ни файла, ни узла, ни состояния.
    final spec = _install([const _FormatterModule('json')]).formatters.single;

    expect(spec.format('  {}  '), '{}');
  });

  test('два форматтера под одним именем — ошибка сборки, а не победа последнего', () {
    // Тихая победа последнего означала бы, что вид документа зависит от
    // порядка модулей в списке, а он там стоит ради приоритета привязок.
    expect(
      () => _install([const _FormatterModule('json'), const _FormatterModule('json', extension: '.jsonc')]),
      throwsA(isA<StateError>()),
    );
  });

  test('разные имена уживаются: форматов много', () {
    final declared =
        _install([const _FormatterModule('json'), const _FormatterModule('xml', extension: '.xml')]).formatters;

    expect(declared.map((spec) => spec.id), ['json', 'xml']);
  });

  test('приложение отдаёт их по убыванию приоритета', () async {
    final runtime = await testApp(
      provider: InMemoryContentProvider([FakeEntry.directory('/home')])..home = '/home',
      modules: [
        const _FormatterModule('low', priority: 10),
        const _FormatterModule('high', priority: 100, extension: '.xml'),
        const _FormatterModule('middle', priority: 50, extension: '.yaml'),
      ],
    );
    await runtime.app.start();

    expect(runtime.app.formatters.map((spec) => spec.id), ['high', 'middle', 'low']);
  });

  test('без объявлений приложение собирается, и список пуст', () async {
    final runtime = await testApp(provider: InMemoryContentProvider([FakeEntry.directory('/home')])..home = '/home');
    await runtime.app.start();

    expect(runtime.app.formatters, isEmpty);
  });
}
