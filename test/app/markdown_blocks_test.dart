import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flex_commander/bootstrap/frontend_registrations.dart';
import 'package:flex_commander/bootstrap/registrations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Модуль, объявляющий рисовальщика врезок.
class _BlockModule implements FcFrontendModule {
  const _BlockModule(this.blockId, {this.priority = 0, this.language = 'mermaid'});

  final String blockId;
  final int priority;
  final String language;

  /// Своё имя у каждого: `installAll` пропускает модуль с уже занятым
  /// идентификатором (`registrations.dart:90`), и два одноимённых модуля
  /// проверяли бы не реестр врезок, а его.
  @override
  String get id => 'test.block.$blockId.$language';

  @override
  String get title => 'Block $blockId';

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.markdownBlock(
      MarkdownBlockSpec(
        id: blockId,
        title: 'Block $blockId',
        priority: priority,
        accepts: (name) => name == language,
        build: (context, request) => const SizedBox.shrink(),
      ),
    );
  }
}

FrontendRegistrations _install(List<FcFrontendModule> modules) =>
    FrontendRegistrations(LazyServices())..installAll(modules);

/// Реестр рисовальщиков врезок markdown: складывает и упорядочивает — и только.
///
/// Решать, чей это язык, ядру нечем; `accepts` спрашивает тот, кто показывает
/// документ (`docs/spec/markdown-viewer.md`, §2).
void main() {
  test('никто не объявил — реестр пуст, и это законный вид приложения', () {
    // Пусто означает «врезки остаются врезками кода», а не «показ сломан».
    expect(_install([]).markdownBlocks, isEmpty);
  });

  test('объявленное складывается', () {
    final declared = _install([const _BlockModule('mermaid')]).markdownBlocks;

    expect(declared, hasLength(1));
    expect(declared.single.id, 'mermaid');
    expect(declared.single.accepts('mermaid'), isTrue);
    expect(declared.single.accepts('dart'), isFalse);
  });

  test('два рисовальщика под одним именем — ошибка сборки, а не победа последнего', () {
    // Тихая победа последнего означала бы, что вид документа зависит от
    // порядка модулей в списке, а он там стоит ради приоритета привязок.
    expect(
      () => _install([const _BlockModule('mermaid'), const _BlockModule('mermaid', language: 'plantuml')]),
      throwsA(isA<StateError>()),
    );
  });

  test('разные имена уживаются: языков много', () {
    final declared =
        _install([const _BlockModule('mermaid'), const _BlockModule('plantuml', language: 'plantuml')]).markdownBlocks;

    expect(declared.map((spec) => spec.id), ['mermaid', 'plantuml']);
  });

  test('приложение отдаёт их по убыванию приоритета', () async {
    final runtime = await testApp(
      provider: InMemoryContentProvider([FakeEntry.directory('/home')])..home = '/home',
      modules: [
        const _BlockModule('low', priority: 10),
        const _BlockModule('high', priority: 100, language: 'plantuml'),
        const _BlockModule('middle', priority: 50, language: 'dot'),
      ],
    );
    await runtime.app.start();

    expect(runtime.app.markdownBlocks.map((spec) => spec.id), ['high', 'middle', 'low']);
  });

  test('без объявлений приложение собирается, и список пуст', () async {
    final runtime = await testApp(provider: InMemoryContentProvider([FakeEntry.directory('/home')])..home = '/home');
    await runtime.app.start();

    expect(runtime.app.markdownBlocks, isEmpty);
  });
}
