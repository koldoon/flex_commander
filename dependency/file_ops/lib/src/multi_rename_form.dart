import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'multi_rename_command.dart';
import 'rename_plan.dart';

/// Форма группового переименования: маски, замена, регистр, счётчик — и
/// таблица предпросмотра под ними.
class MultiRenameForm extends StatefulWidget {
  const MultiRenameForm({super.key, required this.run});

  final MultiRenameRun run;

  @override
  State<MultiRenameForm> createState() => _MultiRenameFormState();
}

class _MultiRenameFormState extends State<MultiRenameForm> {
  /// Сколько строк предпросмотра видно, пока окно не растянули.
  static const int _visibleRows = 12;

  late final TextEditingController _name = TextEditingController(text: widget.run.spec.nameMask);
  late final TextEditingController _extension = TextEditingController(text: widget.run.spec.extensionMask);
  late final TextEditingController _find = TextEditingController(text: widget.run.spec.find);
  late final TextEditingController _replace = TextEditingController(text: widget.run.spec.replace);
  late final TextEditingController _start = TextEditingController(text: '${widget.run.spec.counter.start}');
  late final TextEditingController _step = TextEditingController(text: '${widget.run.spec.counter.step}');
  late final TextEditingController _digits = TextEditingController(text: '${widget.run.spec.counter.digits}');

  @override
  void dispose() {
    _name.dispose();
    _extension.dispose();
    _find.dispose();
    _replace.dispose();
    _start.dispose();
    _step.dispose();
    _digits.dispose();
    super.dispose();
  }

  RenameSpec get _spec => widget.run.spec;

  void _edit(RenameSpec value) => widget.run.edit(value);

  /// Счётчик правится числами: пустое поле значит «как было», а не ноль.
  int _numberOf(String text, int fallback) => int.tryParse(text.trim()) ?? fallback;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final run = widget.run;
    final plan = run.plan;
    final problem = _spec.problem;

    // Ширину назначает само окно, долей экрана: ленивый список на вопрос о
    // своей ширине не отвечает вовсе, а рама без `ownWidth` мерила бы
    // содержимое интринсиками (`docs/spec/dialog-placement.md`).
    return SizedBox(
      width: MediaQuery.sizeOf(context).width * FcTheme.of(context).metrics.paletteWidthFactor,
      child: CommandDialogForm(
        error: null,
        onCancel: run.dismiss,
        // Кнопка гаснет, пока маска негодна, спорят имена или менять нечего.
        onSubmit: run.submit,
        busy: !run.canApply,
        submitLabel: strings.tr('Rename'),
        children: [
          CommandDialogField(
            label: strings.tr('Name'),
            child: FcTextField(
              controller: _name,
              autofocus: true,
              hintText: '[N]',
              onChanged: (value) => _edit(_spec.copyWith(nameMask: value)),
            ),
          ),
          CommandDialogField(
            label: strings.tr('Extension'),
            child: FcTextField(
              controller: _extension,
              hintText: '[E]',
              onChanged: (value) => _edit(_spec.copyWith(extensionMask: value)),
            ),
          ),
          // Ошибка стоит **по ходу набора**, как у выражения в окне поиска: до
          // нажатия «Rename» человек уже знает, что маска не понята.
          if (problem != null) CommandDialogField.wide(child: FcErrorText(message: strings.tr(problem))),
          CommandDialogField(
            label: strings.tr('Find'),
            child: FcTextField(controller: _find, onChanged: (value) => _edit(_spec.copyWith(find: value))),
          ),
          CommandDialogField(
            label: strings.tr('Replace with'),
            child: FcTextField(controller: _replace, onChanged: (value) => _edit(_spec.copyWith(replace: value))),
          ),
          CommandDialogField.wide(
            // Строкой, а пойдёт узко — в две: флажки облегают подпись, и на
            // переводе подлиннее пара их в одну строку уже не влезает.
            child: Wrap(
              spacing: FcTheme.of(context).metrics.dialogSectionGap,
              runSpacing: FcTheme.of(context).metrics.dialogLineGap,
              children: [
                FcCheckbox(
                  label: strings.tr('Regular expression'),
                  value: _spec.regexp,
                  onChanged: (value) => _edit(_spec.copyWith(regexp: value)),
                ),
                FcCheckbox(
                  label: strings.tr('Case sensitive'),
                  value: _spec.caseSensitive,
                  onChanged: (value) => _edit(_spec.copyWith(caseSensitive: value)),
                ),
              ],
            ),
          ),
          // Регистр — двумя строками, а не двумя списками в одной: список
          // облегает самый длинный вариант и ужиматься не умеет, и в узком
          // окне пара таких подписанных списков просто не помещается.
          CommandDialogField(label: strings.tr('Name case'), child: _caseSelect(context, name: true)),
          CommandDialogField(label: strings.tr('Extension case'), child: _caseSelect(context, name: false)),
          // У каждого числа своя подпись: три поля подряд без них — загадка,
          // а не форма.
          CommandDialogField(
            label: strings.tr('Counter'),
            child: Row(
              children: [
                Expanded(
                  child: _titled(
                    context,
                    strings.tr('Start at'),
                    _number(_start, (value) => _spec.counter.copyWith(start: value)),
                  ),
                ),
                SizedBox(width: FcTheme.of(context).metrics.dialogGap),
                Expanded(
                  child: _titled(
                    context,
                    strings.tr('Step by'),
                    _number(_step, (value) => _spec.counter.copyWith(step: value)),
                  ),
                ),
                SizedBox(width: FcTheme.of(context).metrics.dialogGap),
                Expanded(
                  child: _titled(
                    context,
                    strings.tr('Digits'),
                    _number(_digits, (value) => _spec.counter.copyWith(digits: value)),
                  ),
                ),
              ],
            ),
          ),
          CommandDialogField.wide(
            // Своя высота **и** растяжение: `expands` работает только там, где
            // высоту окну задала рама, а без неё таблице нужна собственная — тем
            // же приёмом живёт список находок.
            expands: true,
            indented: false,
            child: SizedBox(
              height: FcTheme.of(context).metrics.rowHeight * _visibleRows,
              child: RenamePreviewTable(plan: plan),
            ),
          ),
          CommandDialogField.wide(indented: false, child: FcText(_summary(context, plan))),
        ],
      ),
    );
  }

  /// Поле с маленькой подписью слева: столбец подписей формы занят общим
  /// именем строки, а полей внутри строки несколько.
  Widget _titled(BuildContext context, String title, Widget field) =>
      Row(children: [FcText(title), SizedBox(width: FcTheme.of(context).metrics.dialogGap), Expanded(child: field)]);

  Widget _caseSelect(BuildContext context, {required bool name}) => FcSelect<RenameCase>(
    options: {for (final value in RenameCase.values) value: context.strings.tr(_caseTitles[value]!)},
    value: name ? _spec.nameCase : _spec.extensionCase,
    onChanged: (value) => _edit(name ? _spec.copyWith(nameCase: value) : _spec.copyWith(extensionCase: value)),
  );

  Widget _number(TextEditingController controller, RenameCounter Function(int) apply) => FcTextField(
    controller: controller,
    onChanged: (value) => _edit(_spec.copyWith(counter: apply(_numberOf(value, 1)))),
  );

  /// Сводка стоит **всегда**: строка, то появляющаяся, то исчезающая, двигала
  /// бы таблицу ровно тогда, когда в неё смотрят.
  String _summary(BuildContext context, RenamePlan plan) {
    final strings = context.strings;
    final parts = [
      strings.plural(plan.rows.length, one: '{n} item', other: '{n} items'),
      strings.plural(plan.changes, one: '{n} to rename', other: '{n} to rename'),
      if (plan.hasCollisions) strings.plural(plan.collisions, one: '{n} collision', other: '{n} collisions'),
    ];
    return parts.join(' · ');
  }

  static const Map<RenameCase, String> _caseTitles = {
    RenameCase.keep: 'Unchanged',
    RenameCase.upper: 'UPPERCASE',
    RenameCase.lower: 'lowercase',
    RenameCase.sentence: 'First capital',
    RenameCase.words: 'Every Word',
  };
}

/// Таблица предпросмотра: было и станет, строка в строку.
///
/// Своя, а не общий виджет: двухколоночной прокручиваемой таблицы с подсветкой
/// отдельных строк в приложении нет, а потребитель у неё пока один. Ленивая
/// нарочно — на пятистах именах `Table` строил бы все ячейки на каждое нажатие
/// клавиши.
class RenamePreviewTable extends StatelessWidget {
  const RenamePreviewTable({super.key, required this.plan});

  final RenamePlan plan;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final strings = context.strings;
    final line = theme.metrics.rowHeight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [Expanded(child: FcLabel(strings.tr('Was'))), Expanded(child: FcLabel(strings.tr('Becomes')))]),
        SizedBox(height: theme.metrics.dialogLineGap),
        Expanded(
          // Плашка — та же, какой обведены все списки в окнах; вплотную:
          // строка упирается в её края.
          child: FcPlate(
            tight: true,
            child: ListView.builder(
              itemCount: plan.rows.length,
              itemExtent: line,
              itemBuilder: (context, index) => _row(context, plan.rows[index]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, RenameRow row) {
    final theme = FcTheme.of(context);
    final colors = theme.colors;
    // Спорная строка — цветом ошибки: роли «предупреждение» в палитре нет, и
    // заводить её ради одного окна значило бы править и тему, и её редактор.
    final tone =
        row.status.collides
            ? colors.error
            : (row.status == RenameStatus.renamed ? colors.rowText : colors.secondaryText);
    final style = theme.dialogTextStyle.copyWith(color: tone);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: theme.metrics.dialogPadding),
      child: Row(
        children: [
          Expanded(child: FcTrimmedText(text: row.from, style: style)),
          Expanded(child: FcTrimmedText(text: row.to, style: style)),
        ],
      ),
    );
  }
}
