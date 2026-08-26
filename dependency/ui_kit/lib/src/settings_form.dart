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

    // Подписи всех разделов разом: столбец у них общий.
    final labelWidth = widestLabel(context, [
      for (final (_, schema) in _pages)
        for (final field in schema.fields)
          // Флаг подписи слева не занимает — она у него справа от квадрата.
          if (field is! SettingsFlag) field.title,
    ]);

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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Разделы — отдельные формы, но столбец подписей у них один
                  // на всё окно: на одной странице они читаются как одна форма,
                  // и ступенька между разделами выглядела бы недосмотром.
                  //
                  // Заголовок раздела при этом идёт во всю ширину — он не
                  // строка формы. У `Table` в Flutter объединения ячеек нет
                  // вовсе, поэтому заголовки живут между таблицами, а не в них.
                  for (final (title, schema) in _pages) ...[
                    _heading(theme, title),
                    FcForm(
                      labelWidth: labelWidth,
                      rows: [for (final field in schema.fields) _row(theme, schema, field)],
                    ),
                    SizedBox(height: metrics.dialogGap),
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

  Widget _heading(FcTheme theme, String title) => Padding(
    padding: EdgeInsets.only(bottom: theme.metrics.dialogLineGap),
    child: Text(
      title,
      style: TextStyle(
        fontFamily: theme.fonts.ui,
        fontSize: theme.metrics.fontSize,
        fontWeight: FontWeight.bold,
        color: theme.colors.dialogTitleText,
      ),
    ),
  );

  /// Поле целиком: управление, подпись и оговорки под ним.
  /// Строка формы: подпись, управление и оговорки под ним.
  ///
  /// Флаг подписи слева не занимает — она у него справа от квадрата; такая
  /// строка идёт во всю ширину столбца значений.
  CommandDialogField _row(FcTheme theme, SettingsSchema schema, SettingsField field) {
    final control = _control(theme, schema, field);
    final explained = [
      control,
      if (field.description.isNotEmpty) Text(field.description, style: _secondaryStyle(theme)),
      // Оговорка отдельной строкой и другим цветом: это не объяснение, а
      // предупреждение — «сейчас ничего не произойдёт».
      if (field.note.isNotEmpty)
        Text(field.note, style: _secondaryStyle(theme).copyWith(color: theme.colors.secondaryText)),
    ];

    if (field is SettingsFlag) {
      return CommandDialogField.wide(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: explained,
        ),
      );
    }

    return explained.length == 1
        ? CommandDialogField(label: field.title, child: control)
        : CommandDialogField.column(label: field.title, children: explained);
  }

  Widget _control(FcTheme theme, SettingsSchema schema, SettingsField field) {
    void changed() {
      schema.save();
      setState(() {});
    }

    return switch (field) {
      SettingsFlag flag => FcCheckbox(
        label: flag.title,
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
          // Поле числа короткое — ему хватает ширины подписи, — но уступает,
          // когда столбец значений узок: иначе единица измерения рядом с ним
          // вылезает за край.
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
