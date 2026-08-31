import 'package:fc_api/fc_api.dart';
import 'package:flutter/material.dart';

import 'command_dialog.dart';
import 'controls.dart';
import 'fc_theme.dart';

/// Настройки списком: разделы модулей, под каждым — его поля.
///
/// Рисует одно место на всё приложение — модуль только перечисляет поля
/// ([SettingsSchema]). Отсюда и единообразие: `Tab` ходит одинаково, флаг
/// выглядит одинаково, а подпись «подействует со следующего запуска» стоит там
/// же, где и у соседа.
///
/// **Настройка — блок, а не строка формы:** подпись, объяснение, управление —
/// сверху вниз, по одной левой границе. Столбца подписей нет нарочно: с ним
/// подпись стояла бы справа, управление слева, а объяснение под управлением, и
/// читать приходилось бы по диагонали. Подробности и образец —
/// `docs/spec/settings-editor.md`.
///
/// Изменение применяется сразу и сразу же просит запись: кнопки «Применить»
/// нет, потому что отменять нечего — приложение и так живёт мгновенным
/// применением темы, колонок и скрытых файлов.
class FcSettingsForm extends StatefulWidget {
  const FcSettingsForm({super.key, required this.pages, required this.onClose});

  final List<SettingsPage> pages;

  /// Закрыть — единственное действие окна.
  final VoidCallback onClose;

  @override
  State<FcSettingsForm> createState() => _FcSettingsFormState();
}

class _FcSettingsFormState extends State<FcSettingsForm> {
  /// Схемы строятся один раз на открытие: они держат замыкания к разделам, и
  /// пересобирать их на каждый кадр незачем.
  late final List<(String, SettingsSchema)> _pages = [for (final page in widget.pages) (page.title, page.build())];

  /// Поля ввода живут столько же, сколько окно: контроллер помнит набранное и
  /// положение курсора, а пересозданный терял бы и то и другое.
  final Map<String, TextEditingController> _editors = {};

  @override
  void dispose() {
    for (final editor in _editors.values) {
      editor.dispose();
    }
    super.dispose();
  }

  TextEditingController _editorFor(String id, String initial) =>
      _editors.putIfAbsent(id, () => TextEditingController(text: initial));

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;

    return ConstrainedBox(
      // Предел по высоте — то же правило, что у справки: без него прокрутка не
      // работает, `Flexible` получает бесконечность, и форма вылезает за экран.
      constraints: dialogContentLimits(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SingleChildScrollView(
              // Те же поля, что и у справки: окна не должны быть отбиты
              // по-разному.
              padding: dialogContentPadding(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (index, (title, schema)) in _pages.indexed) ...[
                    // Просвет **перед** заголовком, а не после каждого раздела:
                    // у первого заголовка сверху уже есть поле окна.
                    if (index > 0) SizedBox(height: metrics.settingsSectionGap),
                    _heading(theme, title),
                    for (final field in schema.fields) ...[
                      SizedBox(height: metrics.settingsBlockGap),
                      _block(theme, schema, title, field),
                    ],
                  ],
                ],
              ),
            ),
          ),
          SizedBox(height: metrics.dialogGap),
          CommandDialogActions(actions: [FcButton(label: 'Close', onPressed: widget.onClose)]),
        ],
      ),
    );
  }

  Widget _heading(FcTheme theme, String title) => Text(
    title,
    style: TextStyle(
      fontFamily: theme.fonts.ui,
      fontSize: theme.metrics.fontSize,
      fontWeight: FontWeight.bold,
      color: theme.colors.dialogTitleText,
    ),
  );

  /// Подпись настройки: «*Категория:* **Имя**».
  ///
  /// Категория — название модуля, тем же цветом, что и объяснения. Она стоит
  /// всегда, хотя заголовок раздела виден рядом: одинаковые подписи у разных
  /// модулей иначе неразличимы — «Wrap long lines» есть и у редактора, и у
  /// просмотрщика текста.
  InlineSpan _titleSpan(FcTheme theme, String category, String title) => TextSpan(
    children: [
      TextSpan(text: '$category: ', style: _secondaryStyle(theme)),
      TextSpan(text: title, style: _labelStyle(theme).copyWith(fontWeight: FontWeight.bold)),
    ],
  );

  /// Настройка целиком: подпись, объяснение, оговорка, управление.
  ///
  /// У флага порядок другой: квадрат встаёт **на строку подписи**, потому что у
  /// него подпись и есть управление. Поставь его как у всех — и подпись
  /// повторилась бы дважды: заголовком и меткой рядом с квадратом.
  Widget _block(FcTheme theme, SettingsSchema schema, String category, SettingsField field) {
    final metrics = theme.metrics;
    final explanations = [
      if (field.description.isNotEmpty) Text(field.description, style: _secondaryStyle(theme)),
      // Оговорка отдельной строкой и другим цветом: это не объяснение, а
      // предупреждение — «сейчас ничего не произойдёт».
      if (field.note.isNotEmpty)
        Text(field.note, style: _secondaryStyle(theme).copyWith(color: theme.colors.secondaryText)),
    ];

    if (field is SettingsFlag) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _control(theme, schema, category, field),
          // Объяснение равняется по подписи, а не по квадрату: оно относится к
          // настройке, а не к галочке.
          if (explanations.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: metrics.dialogLineGap, left: metrics.checkboxSize + metrics.checkboxGap),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: explanations,
              ),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(_titleSpan(theme, category, field.title)),
        for (final line in explanations) ...[SizedBox(height: metrics.dialogLineGap), line],
        SizedBox(height: metrics.dialogLineGap),
        _control(theme, schema, category, field),
      ],
    );
  }

  Widget _control(FcTheme theme, SettingsSchema schema, String category, SettingsField field) {
    void changed() {
      schema.save();
      setState(() {});
    }

    return switch (field) {
      SettingsFlag flag => FcCheckbox(
        label: flag.title,
        richLabel: _titleSpan(theme, category, flag.title),
        value: flag.read(),
        onChanged: (value) {
          flag.write(value);
          changed();
        },
      ),
      SettingsChoice choice => FcRadioGroup<String>(
        options: choice.options,
        value: choice.read(),
        onChanged: (value) {
          choice.write(value);
          changed();
        },
      ),
      SettingsNumber number => Row(
        children: [
          // Поле числа короткое — числа коротки, — но уступает, когда окно
          // узко: иначе единица измерения рядом с ним вылезает за край.
          Flexible(
            child: SizedBox(
              width: theme.metrics.dialogLabelWidth,
              child: FcTextField(
                controller: _editorFor(number.id, '${number.read()}'),
                // Набранное, которое числом не является, просто не применяется:
                // ругаться на «сто» посреди набора хуже, чем подождать, пока
                // человек допишет.
                onChanged: (value) {
                  final parsed = number.parse(value);
                  if (parsed != null) {
                    number.write(parsed);
                    schema.save();
                  }
                },
              ),
            ),
          ),
          if (number.unit.isNotEmpty) ...[
            SizedBox(width: theme.metrics.columnGap),
            Text(number.unit, style: _labelStyle(theme)),
          ],
        ],
      ),
      SettingsText text => FcTextField(
        controller: _editorFor(text.id, text.read()),
        hintText: text.hint,
        onChanged: (value) {
          text.write(value);
          schema.save();
        },
      ),
    };
  }

  TextStyle _labelStyle(FcTheme theme) =>
      TextStyle(fontFamily: theme.fonts.ui, fontSize: theme.metrics.fontSize, color: theme.colors.dialogText);

  TextStyle _secondaryStyle(FcTheme theme) =>
      TextStyle(fontFamily: theme.fonts.ui, fontSize: theme.metrics.fontSize, color: theme.colors.dialogLabel);
}
