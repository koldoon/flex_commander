import 'dart:async';

import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'find_files_state.dart';

/// Окно поиска: маска, флаги, ход работы и то, что нашлось.
class FindFilesForm extends StatefulWidget {
  const FindFilesForm({super.key, required this.state});

  final FindFilesState state;

  @override
  State<FindFilesForm> createState() => _FindFilesFormState();
}

class _FindFilesFormState extends State<FindFilesForm> {
  final TextEditingController _mask = TextEditingController();

  /// Поля, которых пока нет: каталоги-исключения и поиск по содержимому.
  /// Свои контроллеры им нужны затем же, зачем и живому полю, — чтобы поле
  /// было полем, а не картинкой поля.
  final TextEditingController _ignore = TextEditingController();
  final TextEditingController _content = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'find files mask');

  @override
  void initState() {
    super.initState();
    _mask.text = widget.state.query.mask;
  }

  @override
  void dispose() {
    _ignore.dispose();
    _content.dispose();
    _mask.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final state = widget.state;

    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        // Ширина — доля экрана, а не размер содержимого: пути находок бывают
        // длинными и разными, и от них окно прыгало бы на каждой пачке. Тем же
        // ответом снимается вопрос рамы о ширине — а ленивая таблица находок
        // отвечать на него и не умеет.
        return SizedBox(
          width: MediaQuery.sizeOf(context).width * theme.metrics.dialogWidthFactor,
          child: CommandDialogBody(
            // Кнопки идут слева направо к главной, а главная меняется вместе с
            // делом: пока не искали — это «Begin», как только нашлось — «To
            // panel». Обе кнопки про находки до первого поиска не показываются
            // вовсе: мёртвая кнопка, у которой ещё и смысл неочевиден, — это
            // вопрос без ответа.
            // Две кнопки, как в `mc`: спросить и уйти. Всё остальное — дело
            // второго окна, и появляется оно вместе с ним.
            actions: [
              FcButton(label: 'Cancel', onPressed: state.close),
              FcButton(label: 'OK', primary: true, onPressed: state.canStart ? () => unawaited(state.begin()) : null),
            ],
            children: [
              // Раскладка — как в «Find File» у `mc`: сперва откуда искать,
              // потом два столбца — «по имени» и «по содержимому», — и всё это
              // подписями **над** полями, а не слева от них. Слева подпись
              // отняла бы у двух столбцов ту самую ширину, ради которой их и
              // ставят рядом.
              CommandDialogField.wide(
                child: _group(theme, [
                  _labeled(theme, 'Start at:', _startAt(theme, state)),
                  SizedBox(height: theme.metrics.dialogLineGap),
                  // Не наше пока: каталоги-исключения (Д3).
                  FcCheckbox(label: 'Enable ignore directories:', value: false, onChanged: null),
                  SizedBox(height: theme.metrics.dialogLineGap),
                  FcTextField(controller: _ignore, enabled: false),
                ]),
              ),
              CommandDialogField.wide(
                child: _group(theme, [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _byName(theme, state)),
                      SizedBox(width: theme.metrics.dialogHorizontalPadding),
                      Expanded(child: _byContent(theme)),
                    ],
                  ),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Рамка вокруг группы полей — как секции в окне `mc`.
  ///
  /// Рамка та же, что у полей ввода и у таблицы находок: группа — такая же
  /// часть окна, и заводить ей свой вид незачем.
  Widget _group(FcTheme theme, List<Widget> children) {
    final metrics = theme.metrics;
    return Container(
      padding: EdgeInsets.all(metrics.dialogPadding),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colors.inputBorder, width: metrics.strokeWidth),
        borderRadius: BorderRadius.circular(metrics.inputRadius),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }

  /// Подпись **над** полем, как в `mc`.
  Widget _labeled(FcTheme theme, String label, Widget child) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [Text(label, style: theme.dialogLabelStyle), SizedBox(height: theme.metrics.dialogLineGap), child],
    );
  }

  /// Откуда искать: каталог активной панели.
  ///
  /// Показан полем, но не правится: чтобы искать в другом месте, туда переходят
  /// панелью — так не бывает поиска «не там, где думает человек». Кнопок `[^]`
  /// и `[ Tree ]` из `mc` поэтому нет вовсе: выбирать здесь не из чего, и
  /// рисовать мёртвые кнопки, которые никогда не оживут, незачем.
  Widget _startAt(FcTheme theme, FindFilesState state) {
    final metrics = theme.metrics;
    return Container(
      height: metrics.inputHeight,
      alignment: Alignment.centerLeft,
      padding: EdgeInsets.symmetric(horizontal: metrics.inputHorizontalPadding),
      decoration: BoxDecoration(
        color: theme.colors.inputBackground,
        border: Border.all(color: theme.colors.inputBorder, width: metrics.strokeWidth),
        borderRadius: BorderRadius.circular(metrics.inputRadius),
      ),
      child: Text(
        state.where.displayPath,
        style: theme.inputStyle.copyWith(color: theme.colors.inputHint),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// Левый столбец: поиск по имени — то, что уже работает.
  Widget _byName(FcTheme theme, FindFilesState state) {
    final gap = SizedBox(height: theme.metrics.dialogLineGap);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _labeled(
          theme,
          'File name:',
          // `Enter` полю не отдаётся: в открытом окне его разбирает рама и
          // отдаёт окну (`DialogSpec.onSubmit`). Два пути к одному действию
          // разошлись бы в первый же день, когда одному из них добавят условие.
          FcTextField(
            controller: _mask,
            focusNode: _focus,
            autofocus: true,
            hintText: '*.dart;!*.g.dart',
            onChanged: state.typed,
          ),
        ),
        gap,
        FcCheckbox(
          label: 'Find recursively',
          value: state.query.recursive,
          onChanged: state.busy ? null : state.setRecursive,
        ),
        gap,
        // Ссылки не разыменовываются — Д3.
        const FcCheckbox(label: 'Follow symlinks', value: false, onChanged: null),
        gap,
        // Маски у нас всегда «шелловые» — тот же движок, что у пометки, — и
        // выключить это нечем. Стоит отмеченным и приглушённым: так видно, по
        // каким правилам разбирается набранное.
        const FcCheckbox(label: 'Using shell patterns', value: true, onChanged: null),
        gap,
        // Маска сличается без учёта регистра (`FileMask`), и выбора здесь пока
        // нет.
        const FcCheckbox(label: 'Case sensitive', value: false, onChanged: null),
        gap,
        const FcCheckbox(label: 'All charsets', value: false, onChanged: null),
        gap,
        // У `mc` этот флаг перевёрнут относительно нашего: там «пропускать
        // скрытые», у нас в запросе — «брать скрытые». Показываем как в `mc`.
        FcCheckbox(
          label: 'Skip hidden',
          value: !state.query.hidden,
          onChanged: state.busy ? null : (skip) => state.setHidden(!skip),
        ),
      ],
    );
  }

  /// Правый столбец: поиск по содержимому — второй шаг Д2, целиком приглушён.
  Widget _byContent(FcTheme theme) {
    final gap = SizedBox(height: theme.metrics.dialogLineGap);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _labeled(theme, 'Content:', FcTextField(controller: _content, enabled: false)),
        gap,
        const FcCheckbox(label: 'Whole words', value: false, onChanged: null),
        gap,
        const FcCheckbox(label: 'Regular expression', value: false, onChanged: null),
        gap,
        const FcCheckbox(label: 'Case sensitive', value: false, onChanged: null),
        gap,
        const FcCheckbox(label: 'All charsets', value: false, onChanged: null),
        gap,
        const FcCheckbox(label: 'First hit', value: false, onChanged: null),
      ],
    );
  }
}
