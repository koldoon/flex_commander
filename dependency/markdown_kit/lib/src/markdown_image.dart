import 'dart:typed_data';

import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'markdown_style.dart';

/// Чем прочесть картинку, на которую ссылается документ.
///
/// Путь относительный — от каталога самого документа. Разрешает его тот, кто
/// открыл файл: `.md` лежит и в архиве, и на сервере, и читать соседний файл
/// через `dart:io` там нечем (`docs/spec/markdown-viewer.md`, §11).
typedef FcImageResolver = Future<Uint8List> Function(String path);

/// Прочитанные картинки документа и высота, которую они заняли.
///
/// Один на показ. Пока блок с картинкой уезжал за край и возвращался, чтение
/// начиналось заново, а место под картинку на это время схлопывалось в ноль:
/// документ дёргался на каждой прокрутке, а полоса прокрутки прыгала вслед за
/// пересчитанной длиной (`docs/spec/markdown-viewer.md`, §11).
class FcImageStore {
  final Map<String, Future<Uint8List>> _reads = {};
  final Map<String, Uint8List> _ready = {};
  final Map<String, double> _heights = {};

  /// Байты, если они уже прочитаны. Есть — рисуем сразу, без ожидания кадра.
  Uint8List? ready(String key) => _ready[key];

  /// Сколько картинка заняла в прошлый раз; null — ещё не показывали.
  double? heightOf(String key) => _heights[key];

  /// Запомнить занятую высоту: по ней резервируют место, пока идёт чтение.
  void remember(String key, double height) {
    if (height > 0) {
      _heights[key] = height;
    }
  }

  /// Прочитать один раз на документ.
  Future<Uint8List> read(String key, Future<Uint8List> Function() from) =>
      _reads[key] ??= from().then((bytes) {
        _ready[key] = bytes;

        return bytes;
      });

  /// Забыть всё: документ сменился.
  void clear() {
    _reads.clear();
    _ready.clear();
    _heights.clear();
  }
}

/// Картинка из документа.
///
/// Растровую рисует `Image`, векторную — `flutter_svg`: значки в README почти
/// всегда векторные, и показывать их рамкой было бы обиднее всего.
class FcMarkdownImage extends StatefulWidget {
  const FcMarkdownImage({super.key, required this.uri, required this.alt, this.resolve, this.store});

  /// Адрес как он написан в документе.
  final Uri uri;

  /// Подпись — её показывают вместо картинки, когда показать нечего.
  final String alt;

  /// Чем прочесть соседний файл; null — читать нечем.
  final FcImageResolver? resolve;

  /// Прочитанное этим документом; null — своё на каждую картинку.
  final FcImageStore? store;

  @override
  State<FcMarkdownImage> createState() => _FcMarkdownImageState();
}

class _FcMarkdownImageState extends State<FcMarkdownImage> {
  Future<Uint8List>? _bytes;

  /// Своё хранилище, если снаружи не дали: тогда оно живёт ровно столько,
  /// сколько сама картинка.
  FcImageStore? _own;

  /// Им меряют занятую высоту, чтобы запомнить её на следующий показ.
  final GlobalKey _box = GlobalKey();

  FcImageStore get _store => widget.store ?? (_own ??= FcImageStore());

  String get _key => widget.uri.toString();

  /// Удалённая ли картинка. За такими в сеть не ходим (§11).
  bool get _remote => widget.uri.hasScheme && widget.uri.scheme != 'file';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Чтение начинается только для соседнего файла: спросить разрешителя про
    // `https://…` значило бы сходить в сеть его руками.
    if (!_remote) {
      _bytes ??= _store.read(_key, _read);
    }
  }

  /// Запомнить, сколько места картинка заняла.
  void _measure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = _box.currentContext?.findRenderObject();
      if (box is RenderBox && box.hasSize) {
        _store.remember(_key, box.size.height);
      }
    });
  }

  Future<Uint8List> _read() async {
    final resolve = widget.resolve;
    if (resolve == null) {
      throw StateError('нечем прочесть');
    }

    return resolve(widget.uri.toString());
  }

  @override
  Widget build(BuildContext context) {
    // Удалённые картинки не забираем: показ файла не должен молча ходить в
    // сеть (§12). Вместо неё — подпись и адрес, чтобы человек понял, что здесь
    // было и куда смотреть.
    if (_remote) {
      return _placeholder(context, widget.uri.host.isEmpty ? widget.uri.scheme : widget.uri.host);
    }

    // Байты уже есть — рисуем прямо сейчас, без круга через `FutureBuilder`:
    // он и на готовом будущем отдаёт первый кадр пустым, а пустой кадр здесь
    // означает нулевую высоту и прыжок документа.
    final ready = _store.ready(_key);
    if (ready != null) {
      return _picture(context, ready);
    }

    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _placeholder(context, null);
        }
        if (!snapshot.hasData) {
          // Место под картинку держим по прошлому показу: иначе блок
          // схлопывается в ноль и утягивает за собой всё, что ниже.
          return SizedBox(height: _store.heightOf(_key) ?? 0);
        }

        return _picture(context, snapshot.data!);
      },
    );
  }

  Widget _picture(BuildContext context, Uint8List bytes) {
    _measure();

    return KeyedSubtree(
      key: _box,
      child:
          _looksLikeSvg(bytes)
              ? SvgPicture.memory(bytes, fit: BoxFit.scaleDown)
              : Image.memory(
                bytes,
                fit: BoxFit.scaleDown,
                // Байты есть, а кадра ещё нет: расшифровка идёт своим ходом, и
                // до неё у картинки нулевая высота — документ ниже прыгнул бы
                // вверх и обратно. Пока кадра нет, место держим по прошлому
                // показу, как и пока не дочитаны байты.
                //
                // И мерить место — когда кадр пришёл, а не когда собрали
                // виджет: при расшифровке не тем же кадром замер при сборке
                // видел ноль, и настоящая высота не запоминалась никогда.
                frameBuilder: (context, child, frame, synchronous) {
                  if (frame == null && !synchronous) {
                    return SizedBox(height: _store.heightOf(_key) ?? 0);
                  }
                  _measure();
                  return child;
                },
                errorBuilder: (context, _, _) => _placeholder(context, null),
              ),
    );
  }

  /// Вместо картинки — рамка с подписью: пустое место не объясняет ничего.
  Widget _placeholder(BuildContext context, String? source) {
    final theme = FcTheme.of(context);
    final label = widget.alt.trim().isEmpty ? widget.uri.toString() : widget.alt.trim();

    return Container(
      padding: EdgeInsets.all(theme.metrics.dialogPadding),
      decoration: fcCodeBlockDecoration(theme),
      child: Text(
        source == null ? label : '$label — $source',
        style: theme.dialogTextStyle.copyWith(color: theme.colors.secondaryText),
      ),
    );
  }
}

/// Похожи ли байты на векторную картинку.
bool _looksLikeSvg(Uint8List bytes) {
  final head = bytes.length < 512 ? bytes.length : 512;
  final text = String.fromCharCodes(bytes.sublist(0, head));

  return text.contains('<svg');
}
