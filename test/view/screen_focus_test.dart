import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Экран, забирающий фокус, обязан вернуть его, закрываясь.
///
/// Иначе узел, у которого был фокус, исчезает вместе с экраном, и приложение
/// перестаёт слышать клавиатуру целиком — снаружи это выглядит как зависшее
/// окно. Первым таким экраном станет редактор: печатать командами нельзя.
void main() {
  late AppRuntime runtime;

  setUp(() async {
    runtime = await testApp(
      provider: InMemoryTreeProvider([FakeEntry.directory('/home'), FakeEntry.file('/home/notes.txt', size: 10)])
        ..home = '/home',
      modules: [...featureModules(), const _FocusModule()],
    );
    await runtime.app.start();
  });

  testWidgets('открыли, закрыли — и клавиши снова доходят', (tester) async {
    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();

    final wasActive = runtime.app.activePanel;

    runtime.app.view.pushViewportContent(ViewportPosition.fullscreen, _EditorLikeScreen());
    await tester.pumpAndSettle();
    // Фокус внутри экрана: печатать нужно туда, а не в панели.
    expect(find.descendant(of: find.byType(_EditorLikeField), matching: find.byType(TextField)), findsOneWidget);

    runtime.app.view.popViewportContent(ViewportPosition.fullscreen);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    expect(runtime.app.activePanel, isNot(same(wasActive)), reason: 'приложение оглохло после экрана с фокусом');

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('открывшийся экран сразу получает фокус: курсор на месте', (tester) async {
    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();

    runtime.app.view.pushViewportContent(ViewportPosition.fullscreen, _EditorLikeScreen());
    await tester.pumpAndSettle();

    // Без этого человек видит текст, но курсора нет и печатать некуда, пока
    // он не ткнёт мышью.
    expect(FocusManager.instance.primaryFocus?.debugLabel, _EditorLikeScreen.focusLabel);

    runtime.app.view.popViewportContent(ViewportPosition.fullscreen);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('пока экран открыт, набор идёт в него, а не в панели', (tester) async {
    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();

    runtime.app.view.pushViewportContent(ViewportPosition.fullscreen, _EditorLikeScreen());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.descendant(of: find.byType(_EditorLikeField), matching: find.byType(TextField)),
      'печать',
    );
    await tester.pumpAndSettle();

    expect(find.text('печать'), findsOneWidget);

    runtime.app.view.popViewportContent(ViewportPosition.fullscreen);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 20));
  });
}

/// Приносит вид для содержимого-подставки: в ядре своих видов нет.
class _FocusModule implements FcModule {
  const _FocusModule();

  @override
  String get id => 'test.focus';

  @override
  String get title => 'Focus stub';

  @override
  void install(FcRegistry registry) {
    registry.view<_EditorLikeScreen>((context, state) => const _EditorLikeField());
  }
}

/// Содержимое, которому фокус нужен по-настоящему, — как редактору.
///
/// Фокус он **просит сам**: `autofocus` в этот момент не срабатывает — фокус
/// уже у обработчика клавиатуры, и область считает, что хозяин есть.
class _EditorLikeScreen extends ChangeNotifier implements ViewportState {
  _EditorLikeScreen();

  static const String focusLabel = 'editor-like-field';

  @override
  bool get takesKeyboard => true;

  @override
  void close() {}
}

class _EditorLikeField extends StatefulWidget {
  const _EditorLikeField();

  @override
  State<_EditorLikeField> createState() => _EditorLikeFieldState();
}

class _EditorLikeFieldState extends State<_EditorLikeField> {
  final FocusNode _focus = FocusNode(debugLabel: _EditorLikeScreen.focusLabel);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focus.requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) => TextField(focusNode: _focus);

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }
}
