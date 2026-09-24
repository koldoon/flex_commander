import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

/// Справка: оглавление слева, поиск над ним, разделы справа.
///
/// Тем же виджетом устроено окно настроек — разница только в том, что и как
/// отбирается (`docs/spec/help-window.md`).
class HelpView extends StatelessWidget {
  const HelpView({super.key, required this.sections});

  final List<FcTableSection> sections;

  @override
  Widget build(BuildContext context) {
    final metrics = FcTheme.of(context).metrics;

    return SizedBox(
      // Долей экрана, как у настроек: с оглавлением слева ширину окна больше
      // не вывести из содержимого — мерить пришлось бы обе колонки сразу, и
      // окно вышло бы шириной с их сумму (§4).
      width: MediaQuery.sizeOf(context).width * metrics.settingsWidthFactor,
      child: ConstrainedBox(
        // Предел по высоте: без него прокрутка не работает вовсе.
        constraints: dialogContentLimits(context),
        child: FcDialogBody(
          // Листают справку колонки, каждая своей прокруткой.
          scrolls: false,
          insets: FcDialogInsets.none,
          // Кнопок нет: справку читают, а закрывают `Esc`, `Enter` и крестик.
          actions: const [],
          child: FcIndexedSections(
            sections:
                (query) => [
                  for (final section in _found(query)) FcIndexedSection(title: section.title, child: _section(section)),
                ],
            titles: [for (final section in sections) section.title],
            searchHint: 'Search help',
            countLabel: (query) => _countLabel(context, query),
          ),
        ),
      ),
    );
  }

  /// Раздел справки — плашкой с таблицей внутри.
  ///
  /// Столбцы делят **отведённую** ширину долями, а не растут по содержимому:
  /// ширину окну теперь задаёт не таблица, и мерить по самой длинной строке
  /// значило бы вылезти за край (§4). Заодно подписи перестают прыгать на
  /// каждую букву в поиске.
  ///
  /// Столбцов у раздела столько, сколько нужно **ему**: у сведений о сборке их
  /// два, у команд три, — и пустой третий столбец отъедал бы у значения
  /// половину ширины.
  Widget _section(FcTableSection section) {
    final columns = section.columns;
    return FcKeyValueSection(
      section: section,
      widths: List<double>.filled(columns, 0),
      columns: columns,
      divided: true,
      bounded: true,
      // Имя, клавиши, описание: клавиши коротки всегда, а описание длиннее их
      // в разы — поровну делить остаток нельзя.
      shares: columns == 3 ? const [4, 2, 5] : null,
    );
  }

  /// Что осталось от справки под запросом.
  ///
  /// Совпало **название раздела** — раздел показан целиком: спросили
  /// «terminal», значит спросили про все его команды, а не про те, у которых
  /// это слово ещё раз написано в строке (§3).
  List<FcTableSection> _found(String query) {
    if (query.isEmpty) {
      return sections;
    }
    return [
      for (final section in sections)
        if (section.title.toLowerCase().contains(query))
          section
        else if (section.rows.where((row) => _matches(row, query)).toList() case final rows when rows.isNotEmpty)
          FcTableSection(section.title, rows),
    ];
  }

  /// Строка ищется целиком: по названию, по значению и по описанию.
  ///
  /// Значение — это клавиши, а по ним спрашивают не реже, чем по имени: «а что
  /// такое Alt-F9». В первых двух разделах значение — путь панели и версия
  /// сборки, и искать по ним тоже разумно.
  static bool _matches(FcTableRow row, String query) =>
      row.name.toLowerCase().contains(query) ||
      row.value.toLowerCase().contains(query) ||
      row.note.toLowerCase().contains(query);

  /// Сколько строк осталось после отбора: разделов человек и так видит
  /// столько, сколько их в оглавлении.
  String _countLabel(BuildContext context, String query) {
    final count = _found(query).fold(0, (sum, section) => sum + section.rows.length);
    return context.strings.plural(count, one: '{n} row', other: '{n} rows');
  }
}
