import 'dart:typed_data';

import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'markdown_style.dart';

/// Чем прочесть картинку, на которую ссылается документ.
///
/// Путь относительный — от каталога самого документа. Разрешает его тот, кто
/// открыл файл: `.md` лежит и в архиве, и на сервере, и читать соседний файл
/// через `dart:io` там нечем (`docs/spec/markdown-viewer.md`, §10).
typedef FcImageResolver = Future<Uint8List> Function(String path);

/// Картинка из документа.
///
/// Растровую рисует `Image`, векторную — `flutter_svg`: значки в README почти
/// всегда векторные, и показывать их рамкой было бы обиднее всего.
class FcMarkdownImage extends StatefulWidget {
  const FcMarkdownImage({super.key, required this.uri, required this.alt, this.resolve});

  /// Адрес как он написан в документе.
  final Uri uri;

  /// Подпись — её показывают вместо картинки, когда показать нечего.
  final String alt;

  /// Чем прочесть соседний файл; null — читать нечем.
  final FcImageResolver? resolve;

  @override
  State<FcMarkdownImage> createState() => _FcMarkdownImageState();
}

class _FcMarkdownImageState extends State<FcMarkdownImage> {
  Future<Uint8List>? _bytes;

  /// Удалённая ли картинка. За такими в сеть не ходим (§11).
  bool get _remote => widget.uri.hasScheme && widget.uri.scheme != 'file';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Чтение начинается только для соседнего файла: спросить разрешителя про
    // `https://…` значило бы сходить в сеть его руками.
    if (!_remote) {
      _bytes ??= _read();
    }
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

    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _placeholder(context, null);
        }
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final bytes = snapshot.data!;

        return _looksLikeSvg(bytes)
            ? SvgPicture.memory(bytes, fit: BoxFit.scaleDown)
            : Image.memory(bytes, fit: BoxFit.scaleDown, errorBuilder: (context, _, _) => _placeholder(context, null));
      },
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
