import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/services.dart';
import 'package:logecom/logecom.dart';

/// PDF силами системы: документ разбирает и держит раннер, сюда приходят
/// размеры страниц и отрисованные страницы (`docs/spec/pdf-viewer.md`, §3).
///
/// Модуль платформенный и потому стоит рядом с разбором картинок, а не в
/// `dependency/`: без своего раннера канала не существует. Выключишь —
/// просмотрщик PDF откажет и предложит открыть файл системой.
class SystemPdfRendering implements FcFrontendModule {
  const SystemPdfRendering();

  @override
  String get id => 'fc.systemPdf';

  @override
  String get title => 'System PDF rendering';

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.strings('ru', {'System PDF rendering': 'Системная отрисовка PDF'});

    registry.service<SystemPdf>((services) => ChannelSystemPdf());
  }
}

/// Реализация [SystemPdf] поверх канала раннера.
class ChannelSystemPdf implements SystemPdf {
  ChannelSystemPdf({MethodChannel? channel}) : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'flex_commander/pdf';

  final MethodChannel _channel;

  @override
  Future<SystemPdfDocument?> open(Uint8List bytes) async {
    final answer = await _call<Map<Object?, Object?>>('open', {'bytes': bytes});
    if (answer == null) {
      return null;
    }
    final handle = answer['handle'];
    final pages = answer['pages'];
    if (handle is! int || pages is! List) {
      return null;
    }
    return _ChannelPdfDocument(
      this,
      handle,
      pages: _ChannelPdfDocument.pagesOf(pages),
      locked: answer['locked'] == true,
    );
  }

  /// Вызов, который не роняет показ: нет канала или раннер отказал — null и
  /// одна жалоба в журнал.
  Future<T?> _call<T>(String method, Map<String, Object?> arguments) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      _complainOnce(
        'Канала «$channelName» в этом приложении нет: PDF показать нечем. '
        'Раннер собирается заново — горячей перезагрузки для него мало.',
      );
      return null;
    } on PlatformException catch (error) {
      _complainOnce('Раннер отказал в работе с PDF: ${error.message}');
      return null;
    }
  }

  /// Жаловаться один раз за сеанс: страниц много, и жалоба на каждую
  /// превратила бы журнал в шум.
  void _complainOnce(String message) {
    if (_complained) {
      return;
    }
    _complained = true;
    Logecom.createLogger('SystemPdf').warn(message);
  }

  bool _complained = false;
}

class _ChannelPdfDocument implements SystemPdfDocument {
  _ChannelPdfDocument(this._owner, this._handle, {required this.pages, required this.locked});

  static List<Size> pagesOf(List<Object?> pages) => [
    for (final page in pages)
      if (page is List && page.length == 2) Size((page[0] as num).toDouble(), (page[1] as num).toDouble()),
  ];

  final ChannelSystemPdf _owner;
  final int _handle;

  @override
  List<Size> pages;

  @override
  bool locked;

  @override
  Future<bool> unlock(String password) async {
    if (_closed) {
      return false;
    }
    final answer = await _owner._call<Map<Object?, Object?>>('unlock', {'handle': _handle, 'password': password});
    final pages = answer?['pages'];
    if (pages is! List) {
      return false;
    }
    this.pages = pagesOf(pages);
    locked = false;
    return true;
  }

  bool _closed = false;

  @override
  Future<Uint8List?> render(int page, int width) async {
    if (_closed) {
      return null;
    }
    return _owner._call<Uint8List>('render', {'handle': _handle, 'page': page, 'width': width});
  }

  @override
  Future<List<PdfMatch>> find(String text, {required bool caseSensitive}) async {
    if (_closed) {
      return const [];
    }
    final answer = await _owner._call<List<Object?>>('find', {
      'handle': _handle,
      'text': text,
      'caseSensitive': caseSensitive,
    });
    // `[страница, x, y, ширина, высота, x, y, …]` — плоско: так канал везёт
    // это без словарей на каждое место, а их бывают тысячи.
    return [
      for (final entry in answer ?? const [])
        if (entry is List && entry.length >= 5)
          PdfMatch(
            page: (entry[0] as num).toInt(),
            rects: [
              for (var i = 1; i + 3 < entry.length; i += 4)
                Rect.fromLTWH(
                  (entry[i] as num).toDouble(),
                  (entry[i + 1] as num).toDouble(),
                  (entry[i + 2] as num).toDouble(),
                  (entry[i + 3] as num).toDouble(),
                ),
            ],
          ),
    ];
  }

  @override
  Future<List<PdfOutlineItem>> outline() async {
    if (_closed) {
      return const [];
    }
    final answer = await _owner._call<List<Object?>>('outline', {'handle': _handle});
    return [
      for (final entry in answer ?? const [])
        if (entry is List && entry.length == 4)
          PdfOutlineItem(
            depth: (entry[0] as num).toInt(),
            title: entry[1] as String? ?? '',
            target: _targetOf(entry[2], entry[3]),
          ),
    ];
  }

  @override
  Future<List<PdfLink>> links(int page) async {
    if (_closed) {
      return const [];
    }
    final answer = await _owner._call<List<Object?>>('links', {'handle': _handle, 'page': page});
    final links = <PdfLink>[];
    for (final entry in answer ?? const []) {
      if (entry is! List || entry.length < 5) {
        continue;
      }
      final rect = Rect.fromLTWH(
        (entry[0] as num).toDouble(),
        (entry[1] as num).toDouble(),
        (entry[2] as num).toDouble(),
        (entry[3] as num).toDouble(),
      );
      // Пятым идёт адрес — у внешней; страница и доля — у внутренней.
      if (entry[4] case final String url) {
        links.add(PdfLink(rect: rect, url: url));
      } else if (entry.length == 6) {
        links.add(PdfLink(rect: rect, target: _targetOf(entry[4], entry[5])));
      }
    }
    return links;
  }

  /// Место назначения из раннера: доля `-1` — начало страницы.
  static PdfTarget _targetOf(Object? page, Object? top) {
    final fraction = (top as num?)?.toDouble() ?? -1;
    return PdfTarget((page as num).toInt(), top: fraction < 0 ? null : fraction);
  }

  @override
  Future<String> text() async {
    if (_closed) {
      return '';
    }
    return await _owner._call<String>('text', {'handle': _handle}) ?? '';
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _owner._call<void>('close', {'handle': _handle});
  }
}
