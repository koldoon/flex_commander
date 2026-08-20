import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

/// Показ текста: то, чем распоряжается сам виджет.
void main() {
  Future<void> pump(WidgetTester tester, {required bool showLineNumbers}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: const [
            FcTheme(colors: DefaultColors(), metrics: DefaultMetrics(), icons: DefaultIcons(), fonts: DefaultFonts()),
          ],
        ),
        home: Scaffold(
          body: FcCodeView(
            controller: CodeLineEditingController.fromText('раз\nдва\nтри'),
            path: '/home/notes.txt',
            fileName: 'notes.txt',
            readOnly: true,
            showLineNumbers: showLineNumbers,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Курсор моргает по таймеру, пока поле в фокусе: тест обязан его отпустить.
  Future<void> dispose(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets('номера строк показываются, когда их просят', (tester) async {
    await pump(tester, showLineNumbers: true);

    expect(find.byType(DefaultCodeLineNumber), findsOneWidget);

    await dispose(tester);
  });

  testWidgets('без них слева ничего не занимает места', (tester) async {
    await pump(tester, showLineNumbers: false);

    expect(find.byType(DefaultCodeLineNumber), findsNothing);

    await dispose(tester);
  });

  testWidgets('фон рисует рамка, а не поле: иначе полтона разницы с панелью', (tester) async {
    await pump(tester, showLineNumbers: false);

    expect(tester.widget<CodeEditor>(find.byType(CodeEditor)).style?.backgroundColor, isNull);

    await dispose(tester);
  });
}
