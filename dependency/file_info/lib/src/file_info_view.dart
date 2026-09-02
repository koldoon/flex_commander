import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'file_info_screen.dart';

/// Сведения разделами — то, что видно и в окне, и в панели.
///
/// Своей разметки у сведений нет: она общая с справкой и настройками
/// (`FcKeyValueSections`). Здесь только перевод: что рассказали провайдеры — в
/// строки таблицы.
List<FcTableSection> sectionsOf(FileInfoScreen screen) {
  final sections = <FcTableSection>[];

  if (screen.isSummary) {
    sections.add(FcTableSection('Selection', [for (final row in screen.summary) FcTableRow(row.label, row.value)]));
  }

  for (final part in screen.parts) {
    if (part.error case final error?) {
      // Взялся и не смог: это сведение о файле, и место ему здесь же, рядом с
      // остальными сведениями.
      sections.add(FcTableSection(part.title, [FcTableRow('Error', error)]));
      continue;
    }
    if (part.loading) {
      // Идёт — многоточие: молчание непонятно, то ли сведений нет, то ли они
      // не пришли.
      sections.add(FcTableSection('${part.title}…', const []));
      continue;
    }
    for (final section in part.sections) {
      sections.add(FcTableSection(section.title, [for (final row in section.rows) FcTableRow(row.label, row.value)]));
    }
  }

  // Размер каталога сам не считается; в окне для этого кнопка, а здесь строка
  // с ответом, когда его уже посчитали.
  if (screen.directorySize case final size?) {
    sections.add(FcTableSection('Contents', [FcTableRow('Size', formatBytesExact(size))]));
  }

  return sections;
}

/// Сведения в области панели: последний просмотрщик, который берётся за всё.
class FileInfoView extends StatelessWidget {
  const FileInfoView({super.key, required this.screen});

  final FileInfoScreen screen;

  @override
  Widget build(BuildContext context) {
    final app = screen.place == ViewerPlace.panel ? AppScope.read(context) : null;

    return ListenableBuilder(
      listenable: Listenable.merge([screen, if (app != null) app.view]),
      builder:
          (context, _) => FcPanelFrame(
            outerEdge: _edgeOf(app),
            header: FcPathPlate(path: screen.entry.path, active: app == null || app.view.takesKeys(screen)),
            child: Padding(
              padding: EdgeInsets.all(FcTheme.of(context).metrics.labelPadding),
              // Фокуса не просит: сведения в панели читают, а ввод в это время
              // принадлежит списку файлов.
              child: FcKeyValueSections(sections: sectionsOf(screen), autofocus: false, padded: false),
            ),
          ),
    );
  }

  PanelOuterEdge _edgeOf(Application? app) {
    if (app == null) {
      return PanelOuterEdge.both;
    }
    return switch (app.view.positionOf(screen)) {
      ViewportPosition.left => PanelOuterEdge.left,
      ViewportPosition.right => PanelOuterEdge.right,
      _ => PanelOuterEdge.both,
    };
  }
}
