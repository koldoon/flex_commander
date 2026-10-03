import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:fc_ui_api/fc_ui_api.dart';

/// Подписи PDF хватает, чтобы подставная система «разобрала» файл: настоящий
/// разбор — дело раннера, а его в прогоне нет.
const String pdfHeader = '%PDF-1.7\n';

/// Настоящая картинка 6×4: отрисовка страницы в прогоне — она.
final Uint8List pagePng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAYAAAAECAIAAAAiZtkUAAAAFElEQVR4nGM8oaHBgAqY0PhECwEAUwwBIDEmvqgAAAAASUVORK5CYII=',
);

/// Система, которая «открывает» всё, что начинается с `%PDF`.
class FakeSystemPdf implements SystemPdf {
  FakeSystemPdf({
    this.pages = const [Size(600, 800), Size(600, 800), Size(800, 600)],
    this.locked = false,
    this.password,
    this.text = '— 1 —\n\nfirst page\n\n— 2 —\n\nsecond page',
    this.found = const [],
  });

  final List<Size> pages;
  final bool locked;

  /// Чем отпирается запертый; null — ничем.
  final String? password;
  final String text;
  final List<PdfMatch> found;

  /// Все открытые за прогон — по ним видно, закрыты ли.
  final List<FakePdfDocument> opened = [];

  @override
  Future<SystemPdfDocument?> open(Uint8List bytes) async {
    if (!utf8.decode(bytes.take(4).toList(), allowMalformed: true).startsWith('%PDF')) {
      return null;
    }
    final document = FakePdfDocument(this);
    opened.add(document);
    return document;
  }
}

class FakePdfDocument implements SystemPdfDocument {
  FakePdfDocument(this.system);

  final FakeSystemPdf system;

  bool closed = false;

  /// Отперт ли паролем.
  bool unlocked = false;

  /// Какими паролями пробовали отпереть.
  final List<String> tried = [];

  /// Что просили нарисовать: страница и ширина.
  final List<(int, int)> rendered = [];

  /// Что искали.
  final List<(String, bool)> searched = [];

  int textAsked = 0;

  @override
  List<Size> get pages => system.pages;

  @override
  bool get locked => system.locked && !unlocked;

  @override
  Future<bool> unlock(String password) async {
    tried.add(password);
    unlocked = system.password != null && password == system.password;
    return unlocked;
  }

  @override
  Future<Uint8List?> render(int page, int width) async {
    rendered.add((page, width));
    return closed ? null : pagePng;
  }

  @override
  Future<List<PdfMatch>> find(String text, {required bool caseSensitive}) async {
    searched.add((text, caseSensitive));
    return system.found;
  }

  @override
  Future<String> text() async {
    textAsked++;
    return system.text;
  }

  @override
  Future<void> close() async => closed = true;
}

/// Модуль-подставка: в прогоне канала раннера нет, и спрашивать некого.
class FakeSystemPdfModule implements FcFrontendModule {
  const FakeSystemPdfModule(this.system);

  final SystemPdf system;

  @override
  String get id => 'test.pdf';

  @override
  String get title => 'Test PDF';

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.service<SystemPdf>((services) => system);
  }
}
