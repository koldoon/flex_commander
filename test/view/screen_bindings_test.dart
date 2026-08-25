import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/view/function_bar/function_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ряд кнопок показывает команды того экрана, который сейчас виден.
///
/// Ряд — это нарисованная клавиатура: он спрашивает у реестра, что висит на
/// `F1`…`F10`. Значит достаточно, чтобы привязка знала свой экран, — и ряд
/// меняется сам, а кнопка с клавишей разойтись не могут.
void main() {
  late AppRuntime runtime;

  setUp(() async {
    runtime = await testApp(
      provider: InMemoryTreeProvider([FakeEntry.directory('/home'), FakeEntry.file('/home/notes.txt', size: 10)])
        ..home = '/home',
      modules: [...featureModules(), const _StubScreenModule()],
    );
    await runtime.app.start();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();
  }

  String? labelOn(String keys) => runtime.commands.commandFor(KeyCombination.parse(keys))?.label;

  test('в панелях за клавишами стоят панельные команды', () {
    expect(runtime.app.view.contentAt(ViewportPosition.fullscreen), isNull);
    expect(labelOn('F5'), isNotNull);
    expect(labelOn('F2'), isNot('Stub wrap'));
  });

  test('в чужом экране панельные команды молчат, а его — отвечают', () {
    runtime.app.view.pushViewportContent(ViewportPosition.fullscreen, _StubScreen());

    // `F5` принадлежит панелям: копировать из-под чужого экрана нечего.
    expect(labelOn('F5'), isNull);
    expect(labelOn('F2'), 'Stub wrap');
  });

  test('экран закрылся — клавиши вернулись панелям', () {
    runtime.app.view.pushViewportContent(ViewportPosition.fullscreen, _StubScreen());
    runtime.app.view.popViewportContent(ViewportPosition.fullscreen);

    expect(labelOn('F5'), isNotNull);
    expect(labelOn('F2'), isNot('Stub wrap'));
  });

  testWidgets('ряд кнопок следует за экраном, а сам экран занимает место панелей', (tester) async {
    await pumpApp(tester);
    expect(find.text('Stub wrap'), findsNothing);
    expect(find.byType(FunctionButton), findsNWidgets(10));

    runtime.app.view.pushViewportContent(ViewportPosition.fullscreen, _StubScreen());
    await tester.pumpAndSettle();

    // Ряд кнопок остался на месте и показывает команды экрана.
    expect(find.byType(FunctionButton), findsNWidgets(10));
    expect(find.text('Stub wrap'), findsOneWidget);
    // А содержимое панелей сменилось содержимым экрана.
    expect(find.text('Stub screen content'), findsOneWidget);
    expect(find.text('notes'), findsNothing);

    await tester.pump(const Duration(milliseconds: 20));
  });
}

/// Экран-подставка: в ядре своих экранов нет, а проверять правило надо.
class _StubScreen extends ChangeNotifier implements ViewportState {
  _StubScreen();

  @override
  bool get takesKeyboard => false;

  @override
  void close() {}
}

class _StubScreenModule implements FcModule {
  const _StubScreenModule();

  @override
  String get id => 'test.stub_screen';

  @override
  String get title => 'Stub screen';

  @override
  void install(FcRegistry registry) {
    registry.view<_StubScreen>((context, state) => const Center(child: Text('Stub screen content')));
    registry.command((context) => _StubCommand());
    registry.binding(KeyBinding.inState<_StubScreen>('F2', 'stub.wrap'));
  }
}

class _StubCommand extends AppCommand {
  @override
  String get id => 'stub.wrap';

  @override
  String get label => 'Stub wrap';

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute() async {}
}
