import 'dart:async';

import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'find_files_state.dart';
import 'search_limits.dart';

/// Окно поиска: маска, флаги, ход работы и то, что нашлось.
class FindFilesForm extends StatefulWidget {
  const FindFilesForm({super.key, required this.state});

  final FindFilesState state;

  @override
  State<FindFilesForm> createState() => _FindFilesFormState();
}

class _FindFilesFormState extends State<FindFilesForm> {
  final TextEditingController _mask = TextEditingController();

  final TextEditingController _ignore = TextEditingController();

  /// Поля размера и даты: набранное живёт строками до `OK`
  /// (`docs/spec/file-search.md`, §10.5).
  final TextEditingController _sizeFrom = TextEditingController();
  final TextEditingController _sizeTo = TextEditingController();
  final TextEditingController _after = TextEditingController();
  final TextEditingController _before = TextEditingController();

  /// Поля, которого пока нет: поиск по содержимому (Д3). Свой контроллер ему
  /// нужен затем же, зачем и живому полю, — чтобы поле было полем, а не
  /// картинкой поля.
  final TextEditingController _content = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'find files mask');

  @override
  void initState() {
    super.initState();
    _mask.text = widget.state.query.mask;
    // Фокус в маске — и не только просьбой `autofocus`. Просьба разбирается
    // в тот же кадр, в который окно появляется, а в этот кадр фокуса просят и
    // другие: командная строка возвращает его себе, когда ввод числится за ней
    // (`command_line_view.dart`), и всякий, кто слушает `view`. Кто окажется
    // последним, зависит от порядка слушателей, а маска обязана получить фокус
    // всегда: окно затем и открывают, чтобы набрать её.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_focus.hasFocus) {
        _focus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _ignore.dispose();
    _sizeFrom.dispose();
    _sizeTo.dispose();
    _after.dispose();
    _before.dispose();
    _content.dispose();
    _mask.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Набранное в полях размера и даты — одним значением: их разбирают вместе.
  void _limitsTyped(FindFilesState state) {
    state.setLimits(
      SearchLimits(
        sizeFromText: _sizeFrom.text,
        sizeToText: _sizeTo.text,
        afterText: _after.text,
        beforeText: _before.text,
      ),
    );
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
              FcButton(label: context.strings.tr('Cancel'), onPressed: state.close),
              FcButton(
                label: context.strings.tr('OK'),
                primary: true,
                onPressed: state.canStart ? () => unawaited(state.begin()) : null,
              ),
            ],
            // Строки формы — те же, что у всех окон: поля по краям, зазоры
            // между строками и просвет от заголовка ставит `CommandDialogBody`,
            // а не окно поиска своими руками. Своих рамок вокруг групп здесь
            // нет: в `mc` рамка отделяет группу от соседней в текстовом экране,
            // где отделить нечем больше, а у нас группы отбиты воздухом — как
            // во всех остальных окнах.
            //
            // Раскладка при этом остаётся из `mc`: подписи **над** полями и два
            // столбца — «по имени» и «по содержимому». Слева подпись отняла бы
            // у двух столбцов ту самую ширину, ради которой их и ставят рядом.
            children: [
              CommandDialogField.wide(child: _labeled(theme, context.strings.tr('Start at:'), _startAt(theme, state))),
              // Флаг и поле под ним — **один** блок, а не две строки формы:
              // флаг здесь работает подписью к полю, и зазор между ними тот же,
              // что между строками левого столбца. Двумя строками их разделял
              // бы широкий зазор между строками формы, и пара разрывалась — на
              // живой проверке это и было первым, что бросилось в глаза.
              CommandDialogField.wide(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Флажок здесь — выключатель поля, а не условие сам по
                    // себе: снятый очищает исключения, и набранное при этом
                    // остаётся в поле — вдруг вернут.
                    FcCheckbox(
                      label: context.strings.tr('Ignore directories:'),
                      value: state.query.ignore.isNotEmpty,
                      onChanged: state.busy ? null : (on) => state.setIgnore(on ? _ignore.text : ''),
                    ),
                    SizedBox(height: theme.metrics.dialogGap),
                    FcTextField(
                      controller: _ignore,
                      enabled: !state.busy,
                      hintText: 'node_modules;.git',
                      onChanged: state.setIgnore,
                    ),
                  ],
                ),
              ),
              CommandDialogField.wide(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _byName(context, theme, state)),
                    // Просвет между столбцами — по полю окна: тогда средний
                    // просвет читается так же, как боковые.
                    SizedBox(width: theme.metrics.dialogHorizontalPadding),
                    Expanded(child: _byContent(context, theme, state)),
                  ],
                ),
              ),
              // Размер и дата — по ряду на каждое, оба конца рядом: «от … до»
              // читается строкой, а не двумя полями в разных углах.
              CommandDialogField.wide(
                child: Row(
                  children: [
                    Expanded(
                      child: _labeled(
                        theme,
                        context.strings.tr('Size from:'),
                        FcTextField(
                          controller: _sizeFrom,
                          enabled: !state.busy,
                          hintText: '500k',
                          onChanged: (_) => _limitsTyped(state),
                        ),
                      ),
                    ),
                    SizedBox(width: theme.metrics.dialogHorizontalPadding),
                    Expanded(
                      child: _labeled(
                        theme,
                        context.strings.tr('to:'),
                        FcTextField(
                          controller: _sizeTo,
                          enabled: !state.busy,
                          hintText: '2M',
                          onChanged: (_) => _limitsTyped(state),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              CommandDialogField.wide(
                child: Row(
                  children: [
                    Expanded(
                      child: _labeled(
                        theme,
                        context.strings.tr('Changed after:'),
                        FcTextField(
                          controller: _after,
                          enabled: !state.busy,
                          hintText: '7d',
                          onChanged: (_) => _limitsTyped(state),
                        ),
                      ),
                    ),
                    SizedBox(width: theme.metrics.dialogHorizontalPadding),
                    Expanded(
                      child: _labeled(
                        theme,
                        context.strings.tr('before:'),
                        FcTextField(
                          controller: _before,
                          enabled: !state.busy,
                          hintText: '2026-09-01',
                          onChanged: (_) => _limitsTyped(state),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
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
      // Слева, общим правилом: человек должен видеть, **в каком** каталоге
      // ищет, а хвостовое многоточие оставляло от него корень диска.
      child: FcPathText(text: state.where, style: theme.inputStyle.copyWith(color: theme.colors.inputHint)),
    );
  }

  /// Левый столбец: поиск по имени — то, что уже работает.
  Widget _byName(BuildContext context, FcTheme theme, FindFilesState state) {
    // Зазор между флагами — тот же, что форма ставит между своими строками
    // (`FcOptions` разделяет им же варианты одного переключателя): столбец
    // флагов читается столбцом, а не слипшейся стопкой.
    final gap = SizedBox(height: theme.metrics.dialogGap);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _labeled(
          theme,
          context.strings.tr('File name:'),
          Row(
            children: [
              // `Enter` полю не отдаётся: в открытом окне его разбирает рама и
              // отдаёт окну (`DialogSpec.onSubmit`). Два пути к одному действию
              // разошлись бы в первый же день, когда одному из них добавят
              // условие.
              Expanded(
                child: FcTextField(
                  controller: _mask,
                  focusNode: _focus,
                  autofocus: true,
                  hintText: state.query.regexp ? r'\.dart$' : '*.dart;!*.g.dart',
                  onChanged: state.typed,
                ),
              ),
              SizedBox(width: theme.metrics.dialogGap),
              // Переключатель **у поля**, а не флажком в столбце: он говорит не
              // «искать ещё и так», а «как читать набранное». Рядом с полем это
              // видно, а в столбце флагов прочиталось бы как условие.
              _RegexpToggle(
                on: state.query.regexp,
                enabled: !state.busy,
                onChanged: state.setRegexp,
                message: context.strings.tr('Read as a regular expression'),
              ),
            ],
          ),
        ),
        // Неверное выражение — ошибка у поля, а не отказ по нажатию: иначе про
        // опечатку узнают после обхода в сто тысяч каталогов.
        if (!state.query.isValid) ...[
          SizedBox(height: theme.metrics.dialogLineGap),
          Text(
            context.strings.tr('The expression is not understood'),
            style: theme.dialogLabelStyle.copyWith(color: theme.colors.error),
          ),
        ],
        gap,
        FcCheckbox(
          label: context.strings.tr('Find recursively'),
          value: state.query.recursive,
          onChanged: state.busy ? null : state.setRecursive,
        ),
        gap,
        FcCheckbox(
          label: context.strings.tr('Follow symlinks'),
          value: state.query.followLinks,
          onChanged: state.busy ? null : state.setFollowLinks,
        ),
        gap,
        // Один флажок на окно: регистр в имени и в каталогах-исключениях —
        // одно правило, двух в нём не нужно.
        FcCheckbox(
          label: context.strings.tr('Case sensitive'),
          value: state.query.caseSensitive,
          onChanged: state.busy ? null : state.setCaseSensitive,
        ),
        gap,
        // У `mc` этот флаг перевёрнут относительно нашего: там «пропускать
        // скрытые», у нас в запросе — «брать скрытые». Показываем как в `mc`.
        FcCheckbox(
          label: context.strings.tr('Skip hidden'),
          value: !state.query.hidden,
          onChanged: state.busy ? null : (skip) => state.setHidden(!skip),
        ),
      ],
    );
  }

  /// Правый столбец: поиск по содержимому.
  ///
  /// Флажка `First hit` здесь нет: находка у нас — файл, и чтение прекращается
  /// на первом совпадении **всегда**. Флажок обещал бы выбор, которого нет
  /// (`docs/spec/file-search.md`, §11.5).
  Widget _byContent(BuildContext context, FcTheme theme, FindFilesState state) {
    final gap = SizedBox(height: theme.metrics.dialogGap);
    final query = state.query;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _labeled(
          theme,
          context.strings.tr('Content:'),
          FcTextField(
            controller: _content,
            enabled: !state.busy,
            hintText: query.contentRegexp ? r'TODO|FIXME' : 'TODO',
            onChanged: state.setContent,
          ),
        ),
        // Неверное выражение — ошибка у поля, как и у имени.
        if (!query.contentRule.isValid) ...[
          SizedBox(height: theme.metrics.dialogLineGap),
          Text(
            context.strings.tr('The expression is not understood'),
            style: theme.dialogLabelStyle.copyWith(color: theme.colors.error),
          ),
        ],
        gap,
        FcCheckbox(
          label: context.strings.tr('Whole words'),
          value: query.wholeWords,
          onChanged: state.busy ? null : state.setWholeWords,
        ),
        gap,
        // Выражение и «любые кодировки» гасят друг друга: два флажка, которые
        // нельзя включить вместе, лучше показывать так, чем объяснять потом,
        // почему ничего не нашлось.
        FcCheckbox(
          label: context.strings.tr('Regular expression'),
          value: query.contentRegexp,
          onChanged: state.busy ? null : state.setContentRegexp,
        ),
        gap,
        // Свой регистр, отдельно от имени: имя ищут небрежно, а `TODO` от
        // `todo` отличают.
        FcCheckbox(
          label: context.strings.tr('Case sensitive'),
          value: query.contentCase,
          onChanged: state.busy ? null : state.setContentCase,
        ),
        gap,
        FcCheckbox(
          label: context.strings.tr('All charsets'),
          value: query.allCharsets,
          onChanged: state.busy ? null : state.setAllCharsets,
        ),
      ],
    );
  }
}

/// Переключатель у поля имени: читать набранное выражением или маской.
///
/// Квадрат со знаком `.*` — привычка WebStorm и всех, кто держит переключатель
/// **в поле**, а не в списке флагов. Он говорит не «искать ещё и так», а «как
/// читать то, что набрано», и потому стоит там, где набирают.
class _RegexpToggle extends StatelessWidget {
  const _RegexpToggle({required this.on, required this.enabled, required this.onChanged, required this.message});

  final bool on;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  /// Что сказать подсказкой: знак `.*` понятен не всякому.
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;
    final colors = theme.colors;

    return FcTooltip(
      message: message,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? () => onChanged(!on) : null,
            child: Container(
              width: metrics.inputHeight,
              height: metrics.inputHeight,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                // Включённый — залит цветом курсора: тем же, каким в списках
                // отмечено «вот это сейчас и действует».
                color: on ? colors.cursorBackground : colors.inputBackground,
                border: Border.all(color: colors.inputBorder, width: metrics.strokeWidth),
                borderRadius: BorderRadius.circular(metrics.inputRadius),
              ),
              child: Text('.*', style: theme.inputStyle.copyWith(color: on ? colors.cursorText : colors.inputHint)),
            ),
          ),
        ),
      ),
    );
  }
}
