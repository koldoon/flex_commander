import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'attribute_edits.dart';
import 'attributes_run.dart';
import 'mode_edit.dart';

/// Окно правки атрибутов: сетка прав, восьмеричное, владелец, даты,
/// расширенные атрибуты и рекурсия.
class AttributesForm extends StatelessWidget {
  const AttributesForm({super.key, required this.run});

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
        _rights(context, strings.tr('User'), ModeBits.ownerRead, ModeBits.ownerWrite, ModeBits.ownerExecute),
        _rights(context, strings.tr('Group'), ModeBits.groupRead, ModeBits.groupWrite, ModeBits.groupExecute),
        _rights(context, strings.tr('Others'), ModeBits.otherRead, ModeBits.otherWrite, ModeBits.otherExecute),
        _special(context),
        _octal(context),
        if (run.single) _owner(context),
        if (run.single) _date(context, strings.tr('Modified'), run.modifiedText, run.setModified),
        if (run.single) _date(context, strings.tr('Accessed'), run.accessedText, run.setAccessed),
        if (run.single && run.sample.canEditXattrs) ..._extended(context),
        _recursion(context),
      ],
    );
  }

  /// Три флажка одного разряда прав.
  ///
  /// Разрядом в строку, а не сеткой с заголовками: столбец значений в окне
  /// узкий, а `rwx` подряд читается тем же движением, что и `rw-r--r--` в
  /// панели.
  CommandDialogField _rights(BuildContext context, String label, int read, int write, int execute) {
    final strings = context.strings;
    return CommandDialogField(
      label: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _bit(context, strings.tr('read'), read),
          _gap(context),
          _bit(context, strings.tr('write'), write),
          _gap(context),
          _bit(context, strings.tr('execute'), execute),
        ],
      ),
    );
  }

  CommandDialogField _special(BuildContext context) {
    final strings = context.strings;
    return CommandDialogField(
      label: strings.tr('Special'),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _bit(context, 'setuid', ModeBits.setUid),
          _gap(context),
          _bit(context, 'setgid', ModeBits.setGid),
          _gap(context),
          _bit(context, 'sticky', ModeBits.sticky),
        ],
      ),
    );
  }

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

  /// Просвет между флажками в ряду — вдвое против обычного.
  ///
  /// Обычного здесь мало: у флажка справа от клетки уже стоит своя подпись, и
  /// с одним `dialogGap` она смыкалась бы со следующей клеткой в одно слово.
  Widget _gap(BuildContext context) => SizedBox(width: FcTheme.of(context).metrics.dialogGap * 2);

  /// Обычный просвет между управлениями в строке — тот же, что между кнопками.
  static Widget _space(BuildContext context) => SizedBox(width: FcTheme.of(context).metrics.dialogGap);

  /// Восьмеричное — второй вид того же значения, связанный с сеткой в обе
  /// стороны.
  CommandDialogField _octal(BuildContext context) => CommandDialogField(
    label: context.strings.tr('Octal'),
    child: _Field(
      // Ключ по состоянию сетки: поле переписывается, когда его меняют
      // флажками, — и не переписывается, пока в нём набирают.
      key: ValueKey('octal:${run.mode.setBits}:${run.mode.clearBits}'),
      text: run.octalText,
      enabled: run.sample.canEditMode,
      hint: context.strings.tr('mixed'),
      onChanged: run.setOctal,
    ),
  );

  /// Владелец и группа — одной строкой: спрашивают о них вместе.
  CommandDialogField _owner(BuildContext context) {
    final strings = context.strings;
    return CommandDialogField(
      label: strings.tr('Owner'),
      child: Row(
        children: [
          Expanded(
            child: _Field(
              key: ValueKey('owner:${run.sample.uid}'),
              text: run.ownerText,
              enabled: run.sample.canEditOwner,
              hint: strings.tr('user'),
              onChanged: run.setOwner,
            ),
          ),
          _space(context),
          Expanded(
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
        child: _Field(
          key: ValueKey('$label:$text'),
          text: text,
          enabled: run.sample.canEditTimes,
          hint: 'YYYY-MM-DD HH:MM:SS',
          onChanged: onChanged,
        ),
      );

  /// Расширенные атрибуты: что есть, плюс пустая строка под новый.
  ///
  /// **Таблицей, а не рядом строк.** Кнопки в строках разные по подписи
  /// («Remove» длиннее «Add»), и в обычном ряду каждая забирала бы себе по
  /// своей ширине — поля над ней и под ней кончались бы в разных местах, и
  /// столбцы разъезжались. У таблицы столбец кнопок один на все строки и
  /// меряется по самой широкой, а кнопка внутри него прижата влево: короткая
  /// начинается там же, где длинная.
  List<CommandDialogField> _extended(BuildContext context) {
    final strings = context.strings;
    final metrics = FcTheme.of(context).metrics;
    final rows = run.xattrs;
    return [
      CommandDialogField.stacked(
        label: strings.tr('Extended'),
        children: [
          Table(
            // Все три столбца меряются **по себе** — иначе окно не узнает, что
            // ему стоит подрасти, и столбец значения ужмётся до одного знака.
            // (`FlexColumnWidth` в замере отвечает нулём — то же, обо что уже
            // споткнулась форма окна.)
            //
            // У имени сверху предел в половину окна: `com.apple.metadata:
            // kMDItemWhereFroms` иначе съел бы всё место, а ему есть чем
            // ужаться — оно режется многоточием. У значения `flex: 1`: на
            // широком окне остаток достаётся ему.
            columnWidths: {
              0: MinColumnWidth(const IntrinsicColumnWidth(), FixedColumnWidth(metrics.dialogMaxWidth / 2)),
              1: const IntrinsicColumnWidth(flex: 1),
              2: const IntrinsicColumnWidth(),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              for (var i = 0; i < rows.length; i++) _xattrRow(context, rows[i], last: false),
              _newXattrRow(context),
            ],
          ),
        ],
      ),
    ];
  }

  /// Одна строка расширенного атрибута: имя, значение и «убрать».
  TableRow _xattrRow(BuildContext context, Xattr xattr, {required bool last}) {
    final text = xattr.text;
    return TableRow(
      children: [
        _cell(context, FcText(xattr.name, maxLines: 1), last: last, first: true),
        _cell(
          context,
          text == null
              // Двоичное текстом не притворяется: подсунуть человеку испорченную
              // строку хуже, чем не дать её править. Убрать такой атрибут
              // по-прежнему можно — за этим сюда и приходят.
              ? FcText(context.strings.plural(xattr.value.length, one: '{n} byte', other: '{n} bytes'))
              : _Field(
                key: ValueKey('xattr:${xattr.name}'),
                text: text,
                enabled: true,
                hint: '',
                onChanged: (value) => run.setXattr(xattr.name, value),
              ),
          last: last,
        ),
        _cell(
          context,
          FcButton(label: context.strings.tr('Remove'), onPressed: () => run.removeXattr(xattr.name)),
          last: last,
        ),
      ],
    );
  }

  /// Пустая строка, которой заводят новый атрибут.
  TableRow _newXattrRow(BuildContext context) {
    final strings = context.strings;
    // Ключ по числу правок: поля пустеют, когда атрибут добавлен.
    final key = '${run.xattrSet.length}:${run.xattrRemove.length}';
    return TableRow(
      children: [
        _cell(
          context,
          _Field(
            key: ValueKey('new-name:$key'),
            text: run.newXattrName,
            enabled: true,
            hint: strings.tr('name'),
            onChanged: run.setNewXattrName,
          ),
          last: true,
          first: true,
        ),
        _cell(
          context,
          _Field(
            key: ValueKey('new-value:$key'),
            text: run.newXattrValue,
            enabled: true,
            hint: strings.tr('value'),
            onChanged: run.setNewXattrValue,
          ),
          last: true,
        ),
        _cell(context, FcButton(label: strings.tr('Add'), onPressed: run.addXattr), last: true),
      ],
    );
  }

  /// Ячейка таблицы: просвет слева — между столбцами, снизу — между строками.
  ///
  /// Кнопка внутри прижата влево: столбец мерян по самой широкой из них, и без
  /// этого короткая встала бы посередине отведённого ей места.
  Widget _cell(BuildContext context, Widget child, {required bool last, bool first = false}) {
    final gap = FcTheme.of(context).metrics.dialogGap;
    return Padding(
      padding: EdgeInsets.only(left: first ? 0 : gap, bottom: last ? 0 : gap),
      child: Align(alignment: Alignment.centerLeft, child: child),
    );
  }

  /// Рекурсия и отбор — одной строкой, как «идти по ссылкам» у переноса.
  CommandDialogField _recursion(BuildContext context) {
    final strings = context.strings;
    return CommandDialogField.wide(
      child: Row(
        children: [
          FcCheckbox(
            label: strings.tr('Recursive'),
            value: run.recursive,
            // Показан, но погашен, когда каталогов среди целей нет: пропадающее
            // поле переставляет всё, что под ним, прямо под курсором человека.
            onChanged: run.hasDirectory ? run.setRecursive : null,
          ),
          _gap(context),
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
        ],
      ),
    );
  }
}

/// Поле ввода со своим владельцем текста.
///
/// Отдельным виджетом ради контроллера: форма перерисовывается на каждую
/// правку, а контроллер обязан пережить перерисовку — иначе курсор прыгает в
/// начало на каждой набранной букве.
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
