import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';

/// Ячейка колонки «Type»: что это за файл — по первым байтам, а не по имени.
///
/// Спрашивает службу **сама**, на своей стороне: везти тип через границу
/// незачем — байты и так берутся отсюда (`docs/spec/content-types.md`, §2а).
///
/// Ответ приходит дважды, и это тот же приём, что у значка: известное —
/// сразу, прочитанное — перерисовкой. Пока ответа нет, ячейка пуста: догадка
/// по расширению здесь была бы ложью ровно в том месте, ради которого колонка
/// и заведена.
class ContentTypeCell extends StatefulWidget {
  const ContentTypeCell({required this.entry, required this.selected, this.contentOf, this.types, super.key});

  /// Чем называется каталог: коротко и по-техничному, как в mc. Не переводится
  /// — это метка, а не фраза (`docs/spec/localization.md`, §3).
  static const String directoryTitle = 'DIR';

  final FileEntry entry;

  /// Строка под курсором: её текст белый, как и у соседних ячеек.
  final bool selected;

  /// Чем открыть байты строки; null — открыть нечем, и тип не узнать.
  final Content Function(FileEntry entry)? contentOf;

  /// Служба; null — модуль выключен, и колонки быть не должно вовсе.
  final ContentTypes? types;

  @override
  State<ContentTypeCell> createState() => _ContentTypeCellState();
}

class _ContentTypeCellState extends State<ContentTypeCell> {
  ContentType? _type;

  /// Строка, про которую спрашивали: список ленивый, и та же ячейка достаётся
  /// другому файлу при прокрутке.
  String _askedFor = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ask();
  }

  @override
  void didUpdateWidget(ContentTypeCell old) {
    super.didUpdateWidget(old);
    _ask();
  }

  /// Что написать в ячейке.
  ///
  /// Каталог называется `DIR` — как в mc: это не «неизвестный тип», а вполне
  /// определённый ответ, и пустая ячейка у каталога читалась бы как «ещё не
  /// прочитали». Байты у него при этом никто не берёт: каталог — не файл, и
  /// про него отвечает не служба, а сама строка
  /// (`docs/spec/content-types.md`, §2а).
  ///
  /// У «..» пусто: это не объект, а дорога наверх, и типа у неё нет.
  String _titleOf(FileEntry entry) => switch (entry.kind) {
    EntryKind.parent => '',
    EntryKind.directory => ContentTypeCell.directoryTitle,
    _ => _type?.title ?? '',
  };

  void _ask() {
    final types = widget.types;
    final entry = widget.entry;
    if (types == null || entry.path == _askedFor) {
      return;
    }
    _askedFor = entry.path;
    _type = types.known(entry);
    if (_type != null) {
      return;
    }

    final open = widget.contentOf;
    if (open == null) {
      return;
    }
    // `stillWanted` — служба сама бросит чтение, если строка уехала с экрана:
    // очередь у неё общая, и читать для того, кого уже не видно, незачем.
    unawaited(
      types.detect(entry, () => open(entry), stillWanted: () => mounted && entry.path == _askedFor).then((type) {
        if (mounted && type != null && entry.path == _askedFor) {
          setState(() => _type = type);
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _titleOf(widget.entry);
    if (title.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = FcTheme.of(context);
    final metrics = theme.metrics;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: metrics.cellPadding),
      child: Align(
        alignment: Alignment.centerLeft,
        // Тот же сдвиг, что у остальных ячеек: текст опущен относительно
        // иконки (`FcMetrics.rowTextVerticalNudge`).
        child: Transform.translate(
          offset: Offset(0, metrics.rowTextVerticalNudge),
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: widget.selected ? theme.rowStyle.copyWith(color: theme.colors.cursorText) : theme.rowStyle,
          ),
        ),
      ),
    );
  }
}
