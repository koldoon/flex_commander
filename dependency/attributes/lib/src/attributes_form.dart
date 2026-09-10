import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart' show Tooltip;
import 'package:flutter/widgets.dart';

import 'attribute_edits.dart';
import 'attributes_run.dart';
import 'mode_edit.dart';

/// Окно правки атрибутов.
///
/// Раскладка — по образцу `docs/design/permissions/Attributes Dialog.dc.html`:
/// восьмеричное с расшифровкой сверху, четыре карточки разрядов в ряд, поля
/// владельца и дат, список расширенных атрибутов с прокруткой и строка «куда
/// применить».
class AttributesForm extends StatelessWidget {
  const AttributesForm({super.key, required this.run});

  /// Ширины полей — из того же образца. Числами, потому что это раскладка
  /// одного окна, а не роль темы: дата занимает ровно `2026-09-09 02:06:59`,
  /// восьмеричное — четыре цифры, и растягивать их не на что.
  static const double _octalWidth = 78;
  static const double _fieldWidth = 170;

  /// Пределы столбцов расширенных атрибутов — `minmax()` образца.
  ///
  /// Нижний нужен, чтобы столбец не схлопнулся в один знак; верхний — чтобы
  /// `com.apple.metadata:kMDItemWhereFroms` не съел всё место: ужиматься ему
  /// есть чем, он режется многоточием.
  static const double _nameMin = 90;
  static const double _nameMax = 200;
  static const double _valueMin = 120;
  static const double _valueMax = 240;

  /// Сколько строк расширенных видно сразу; дальше — прокрутка.
  static const int _visibleXattrs = 4;

  final AttributesRun run;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return CommandDialogForm(
      error: run.error,
      onCancel: run.dismiss,
      onSubmit: run.submit,
      submitLabel: strings.tr('Apply'),
      children: [
        CommandDialogField.wide(child: _octalRow(context)),
        CommandDialogField.wide(child: _classes(context)),
        if (run.single) _owner(context),
        if (run.single) _date(context, strings.tr('Modified'), run.modifiedText, run.setModified),
        if (run.single) _date(context, strings.tr('Accessed'), run.accessedText, run.setAccessed),
        if (run.single && run.sample.canEditXattrs) ..._extended(context),
        CommandDialogField.wide(child: _applyTo(context)),
      ],
    );
  }

  /// Восьмеричное, строка режима и расшифровка словами — одной строкой.
  ///
  /// Три вида одного значения рядом: набирают восьмеричное, читают `rw-r--r--`,
  /// а словами видно, кому что досталось, не считая букв по разрядам.
  Widget _octalRow(BuildContext context) {
    final theme = FcTheme.of(context);
    final strings = context.strings;
    return Row(
      children: [
        FcLabel(strings.tr('Octal')),
        SizedBox(width: theme.metrics.dialogGap),
        SizedBox(
          width: _octalWidth,
          child: _Field(
            // Ключ по состоянию сетки: поле переписывается, когда его меняют
            // флажками, — и не переписывается, пока в нём набирают.
            key: ValueKey('octal:${run.mode.setBits}:${run.mode.clearBits}'),
            text: run.octalText,
            enabled: run.sample.canEditMode,
            hint: strings.tr('mixed'),
            onChanged: run.setOctal,
          ),
        ),
        SizedBox(width: theme.metrics.dialogGap),
        Flexible(child: FcText(_modeString(context), maxLines: 1)),
      ],
    );
  }

  /// Четыре разряда карточками в ряд: владелец, группа, остальные, особые.
  Widget _classes(BuildContext context) {
    final strings = context.strings;
    // `IntrinsicHeight` — чтобы карточки были одной высоты: без него растяжка
    // в столбце без предела высоты требует бесконечности, а по содержимому они
    // разойдутся на пару точек и рамки перестанут стоять в линию.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _card(context, strings.tr('User'), ModeBits.ownerRead, ModeBits.ownerWrite, ModeBits.ownerExecute),
          ),
          _space(context),
          Expanded(
            child: _card(context, strings.tr('Group'), ModeBits.groupRead, ModeBits.groupWrite, ModeBits.groupExecute),
          ),
          _space(context),
          Expanded(
            child: _card(context, strings.tr('Others'), ModeBits.otherRead, ModeBits.otherWrite, ModeBits.otherExecute),
          ),
          _space(context),
          Expanded(child: _special(context)),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, String title, int read, int write, int execute) {
    final strings = context.strings;
    return _Card(
      title: title,
      children: [
        _bit(context, strings.tr('read'), read),
        _bit(context, strings.tr('write'), write),
        _bit(context, strings.tr('exec'), execute),
      ],
    );
  }

  Widget _special(BuildContext context) => _Card(
    title: context.strings.tr('Special'),
    children: [
      _bit(context, 'setuid', ModeBits.setUid),
      _bit(context, 'setgid', ModeBits.setGid),
      _bit(context, 'sticky', ModeBits.sticky),
    ],
  );

  /// Флажок одного бита.
  ///
  /// Третье состояние — только там, где ему есть что означать: бит разошёлся у
  /// выбранных объектов. Где значение у всех одно, «не трогать» неотличимо от
  /// «оставить как есть» (работе уезжает лишь то, что изменили), а лишний шаг
  /// по кругу означал бы два нажатия вместо одного, чтобы поднять право.
  Widget _bit(BuildContext context, String label, int bit) {
    final enabled = run.sample.canEditMode;
    if (run.initialMode.valueOf(bit) == null && !run.initialMode.isEmpty) {
      return FcCheckbox.tristate(
        label: label,
        value: run.mode.valueOf(bit),
        onChanged: enabled ? (value) => run.setBit(bit, value) : null,
      );
    }
    return FcCheckbox(
      label: label,
      value: run.mode.valueOf(bit) ?? false,
      onChanged: enabled ? (value) => run.setBit(bit, value) : null,
    );
  }

  /// Владелец и группа — одной строкой: спрашивают о них вместе.
  CommandDialogField _owner(BuildContext context) {
    final strings = context.strings;
    return CommandDialogField(
      label: strings.tr('Owner'),
      child: Row(
        children: [
          SizedBox(
            width: _fieldWidth,
            child: _Field(
              key: ValueKey('owner:${run.sample.uid}'),
              text: run.ownerText,
              enabled: run.sample.canEditOwner,
              hint: strings.tr('user'),
              onChanged: run.setOwner,
            ),
          ),
          _space(context),
          SizedBox(
            width: _fieldWidth,
            child: _Field(
              key: ValueKey('group:${run.sample.gid}'),
              text: run.groupText,
              enabled: run.sample.canEditOwner,
              hint: strings.tr('group'),
              onChanged: run.setGroup,
            ),
          ),
        ],
      ),
    );
  }

  CommandDialogField _date(BuildContext context, String label, String text, ValueChanged<String> onChanged) =>
      CommandDialogField(
        label: label,
        child: Row(
          children: [
            SizedBox(
              width: _fieldWidth,
              child: _Field(
                key: ValueKey('$label:$text'),
                text: text,
                enabled: run.sample.canEditTimes,
                hint: 'YYYY-MM-DD HH:MM:SS',
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      );

  /// Расширенные атрибуты: заголовок со счётом, список с прокруткой и строка
  /// под новый.
  ///
  /// **Список — таблицей**: столбцы у строк общие, иначе значение начиналось бы
  /// у каждой строки в своём месте. Видно [_visibleXattrs] строк, дальше
  /// прокрутка: у файла с диска их бывает и десяток, а окно не должно расти без
  /// предела.
  List<CommandDialogField> _extended(BuildContext context) {
    final theme = FcTheme.of(context);
    final strings = context.strings;
    final rows = run.xattrs;
    final rowHeight = theme.metrics.inputHeight + theme.metrics.dialogLineGap * 2;

    return [
      CommandDialogField.wide(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FcLabel(strings.tr('Extended attributes')),
            SizedBox(width: theme.metrics.dialogGap),
            FcText(strings.plural(rows.length, one: '{n} attribute', other: '{n} attributes')),
          ],
        ),
      ),
      CommandDialogField.wide(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (rows.isNotEmpty)
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: rowHeight * _visibleXattrs),
                child: SingleChildScrollView(
                  child: Table(
                    columnWidths: const {
                      0: IntrinsicColumnWidth(flex: 1),
                      1: IntrinsicColumnWidth(),
                      2: IntrinsicColumnWidth(flex: 1),
                      3: IntrinsicColumnWidth(),
                    },
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    children: [for (final one in rows) _xattrRow(context, one)],
                  ),
                ),
              ),
            SizedBox(height: theme.metrics.dialogLineGap),
            _newXattrRow(context),
          ],
        ),
      ),
    ];
  }

  TableRow _xattrRow(BuildContext context, Xattr xattr) {
    final theme = FcTheme.of(context);
    final strings = context.strings;
    final text = xattr.text;
    return TableRow(
      children:
          [
            _cell(
              context,
              first: true,
              // Полное имя — подсказкой: в столбце оно режется многоточием, а
              // спрашивают о нём именно тогда, когда не влезло.
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: _nameMin, maxWidth: _nameMax),
                child: Tooltip(message: xattr.name, child: FcText(xattr.name, maxLines: 1)),
              ),
            ),
            _cell(context, FcLabel(strings.plural(xattr.value.length, one: '{n} byte', other: '{n} bytes'))),
            _cell(
              context,
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: _valueMin, maxWidth: _valueMax),
                child: Tooltip(
                  message: text ?? strings.tr('binary'),
                  child: _Field(
                    key: ValueKey('xattr:${xattr.name}'),
                    // Двоичное текстом не притворяется: подсунуть человеку
                    // испорченную строку хуже, чем показать пустое поле с
                    // подсказкой. Набранное в нём заменит двоичное целиком — это
                    // осознанный ввод, а не порча несмотренного.
                    text: text ?? '',
                    enabled: true,
                    hint: text == null ? strings.tr('binary') : '',
                    onChanged: (value) => run.setXattr(xattr.name, value, wasBinary: text == null),
                  ),
                ),
              ),
            ),
            _cell(context, FcButton(label: strings.tr('Remove'), onPressed: () => run.removeXattr(xattr.name))),
            // Просвет между строками — снизу у каждой ячейки, кроме последней.
          ].map((cell) => Padding(padding: EdgeInsets.only(bottom: theme.metrics.dialogLineGap), child: cell)).toList(),
    );
  }

  /// Пустая строка, которой заводят новый атрибут.
  Widget _newXattrRow(BuildContext context) {
    final strings = context.strings;
    // Ключ по числу правок: поля пустеют, когда атрибут добавлен.
    final key = '${run.xattrSet.length}:${run.xattrRemove.length}';
    return Row(
      children: [
        Expanded(
          flex: 10,
          child: _Field(
            key: ValueKey('new-name:$key'),
            text: run.newXattrName,
            enabled: true,
            hint: strings.tr('name'),
            onChanged: run.setNewXattrName,
          ),
        ),
        _space(context),
        Expanded(
          flex: 13,
          child: _Field(
            key: ValueKey('new-value:$key'),
            text: run.newXattrValue,
            enabled: true,
            hint: strings.tr('value'),
            onChanged: run.setNewXattrValue,
          ),
        ),
        _space(context),
        FcButton(label: strings.tr('Add'), onPressed: run.addXattr),
      ],
    );
  }

  /// Куда применить: отбор и признак «внутрь каталогов».
  Widget _applyTo(BuildContext context) {
    final strings = context.strings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FcLabel(strings.tr('Apply to')),
        SizedBox(height: FcTheme.of(context).metrics.dialogLineGap),
        Row(
          children: [
            FcSelect<AttributeScope>(
              options: {
                AttributeScope.all: strings.tr('files and directories'),
                AttributeScope.files: strings.tr('only files'),
                AttributeScope.directories: strings.tr('only directories'),
              },
              value: run.applyTo,
              // Отбор относится к тому, что нашлось внутри, — без рекурсии ему
              // нечего отбирать.
              onChanged: run.recursive && run.hasDirectory ? run.setApplyTo : null,
            ),
            _space(context),
            FcCheckbox(
              label: strings.tr('Recursive'),
              value: run.recursive,
              // Показан, но погашен, когда каталогов среди целей нет:
              // пропадающее поле переставляет всё, что под ним, прямо под
              // курсором человека.
              onChanged: run.hasDirectory ? run.setRecursive : null,
            ),
          ],
        ),
      ],
    );
  }

  /// Строка режима по нынешней сетке: `-rw-r--r--`.
  ///
  /// Считается по правке, а не берётся у источника: она и показывает, что
  /// получится, а не что было. Бит «не трогать» пишется вопросом — у него нет
  /// ответа до самой работы.
  String _modeString(BuildContext context) {
    const letters = 'rwxrwxrwx';
    final type = run.sample.modeString.isEmpty ? '-' : run.sample.modeString[0];
    final buffer = StringBuffer(type);
    const order = [
      ModeBits.ownerRead,
      ModeBits.ownerWrite,
      ModeBits.ownerExecute,
      ModeBits.groupRead,
      ModeBits.groupWrite,
      ModeBits.groupExecute,
      ModeBits.otherRead,
      ModeBits.otherWrite,
      ModeBits.otherExecute,
    ];
    for (var i = 0; i < order.length; i++) {
      buffer.write(switch (run.mode.valueOf(order[i])) {
        true => letters[i],
        false => '-',
        null => '?',
      });
    }
    return buffer.toString();
  }

  /// Ячейка таблицы: просвет слева — между столбцами.
  Widget _cell(BuildContext context, Widget child, {bool first = false}) => Padding(
    padding: EdgeInsets.only(left: first ? 0 : FcTheme.of(context).metrics.dialogGap),
    child: Align(alignment: Alignment.centerLeft, child: child),
  );

  static Widget _space(BuildContext context) => SizedBox(width: FcTheme.of(context).metrics.dialogGap);
}

/// Карточка разряда прав: подпись и три флажка столбиком.
class _Card extends StatelessWidget {
  const _Card({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    return Container(
      padding: EdgeInsets.all(theme.metrics.dialogGap),
      decoration: BoxDecoration(
        color: theme.colors.dialogListBackground,
        border: Border.all(color: theme.colors.dialogListBorder, width: theme.metrics.strokeWidth),
        borderRadius: BorderRadius.circular(theme.metrics.inputRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FcLabel(title),
          SizedBox(height: theme.metrics.dialogLineGap),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: theme.metrics.dialogLineGap),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Поле ввода со своим владельцем текста.
///
/// Отдельным виджетом ради контроллера: форма перерисовывается на каждую
/// правку, а контроллер обязан пережить перерисовку — иначе курсор прыгает в
/// начало на каждой набранной букве. Он же держит прокрутку внутри поля: в
/// длинном значении видно то место, где стоит курсор.
class _Field extends StatefulWidget {
  const _Field({super.key, required this.text, required this.enabled, required this.hint, required this.onChanged});

  final String text;
  final bool enabled;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  late final TextEditingController _controller = TextEditingController(text: widget.text);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FcTextField(controller: _controller, enabled: widget.enabled, hintText: widget.hint, onChanged: widget.onChanged);
}
