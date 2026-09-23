import 'package:fc_api/fc_api.dart';
import 'package:fc_content_types/fc_content_types.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Колонка «Type»: что за файл — по первым байтам, а не по имени
/// (`docs/spec/content-types.md`, §2а).
void main() {
  /// Байты, которые служба прочитает: подпись PNG.
  final png = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, ...List.filled(64, 0)];

  FileEntry file(String name) => FileEntry(name: name, kind: EntryKind.file, path: '/home/$name', size: 128);

  Widget cellOf(FileEntry entry, {ContentTypes? types, Content Function(FileEntry entry)? contentOf}) => MaterialApp(
    theme: ThemeData(
      extensions: [
        FcTheme(colors: DefaultColors(), metrics: DefaultMetrics(), icons: DefaultIcons(), fonts: DefaultFonts()),
      ],
    ),
    home: Scaffold(
      body: SizedBox(
        width: 120,
        child: ContentTypeCell(entry: entry, selected: false, types: types, contentOf: contentOf),
      ),
    ),
  );

  testWidgets('пока ответа нет — пусто, а не догадка по имени', (tester) async {
    // Имя врёт: расширение `.png` у файла, который ещё не читали. Показать по
    // нему «PNG image» значило бы соврать ровно в том месте, ради которого
    // колонка и заведена.
    final service = ContentTypeService(concurrency: () => 1);
    await tester.pumpWidget(cellOf(file('photo.png'), types: service, contentOf: (_) => _HeldContent()));

    expect(find.byType(Text), findsNothing);
  });

  testWidgets('байты прочитались — ячейка перерисовала себя', (tester) async {
    final service = ContentTypeService(concurrency: () => 1);
    // Имя ни при чём: файл зовётся `photo.dat`, а внутри — картинка.
    await tester.pumpWidget(cellOf(file('photo.dat'), types: service, contentOf: (_) => _BytesContent(png)));

    await tester.pumpAndSettle();

    expect(find.text('PNG image'), findsOneWidget);
  });

  testWidgets('службы нет — колонка молчит', (tester) async {
    await tester.pumpWidget(cellOf(file('photo.png')));
    await tester.pumpAndSettle();

    expect(find.byType(Text), findsNothing);
  });

  testWidgets('каталог зовётся DIR и байтов не отдаёт', (tester) async {
    final service = ContentTypeService(concurrency: () => 1);
    var opened = 0;
    await tester.pumpWidget(
      cellOf(
        FileEntry(name: 'docs', path: '/home/docs', kind: EntryKind.directory),
        types: service,
        contentOf: (_) {
          opened++;
          return _BytesContent(png);
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('DIR'), findsOneWidget, reason: 'как в mc: это ответ, а не «ещё не прочитали»');
    expect(opened, 0, reason: 'байты у каталога никто не берёт');
  });

  testWidgets('у «..» типа нет вовсе', (tester) async {
    final service = ContentTypeService(concurrency: () => 1);
    await tester.pumpWidget(cellOf(FileEntry(name: '..', path: '', kind: EntryKind.parent), types: service));
    await tester.pumpAndSettle();

    expect(find.byType(Text), findsNothing, reason: '«..» — дорога наверх, а не объект');
  });
}

/// Содержимое, которое отдаёт байты сразу.
class _BytesContent implements Content {
  _BytesContent(this.bytes);

  final List<int> bytes;

  @override
  int get length => bytes.length;

  @override
  Stream<List<int>> read({int offset = 0}) async* {
    yield bytes.sublist(offset);
  }
}

/// Содержимое, которое молчит: ответа не будет.
class _HeldContent implements Content {
  @override
  int get length => 1024;

  @override
  Stream<List<int>> read({int offset = 0}) => const Stream<List<int>>.empty();
}
