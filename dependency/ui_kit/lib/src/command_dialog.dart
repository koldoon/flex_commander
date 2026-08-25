import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

import 'package:fc_api/fc_api.dart';
import 'fc_theme.dart';

/// Готовые куски содержимого окна команды.
///
/// Рамку и заголовок рисует ядро, а внутренности — команда. Чтобы окна разных
/// команд выглядели одинаково, типовые случаи собраны здесь: форма с полем
/// ввода, подтверждение, ход выполнения и вопрос по ходу работы.
///
/// Вид взят у референса: содержимое с полями `padding="20" paddingLeft="40"`,
/// под ним линия и ряд кнопок, прижатых вправо (`TitledPopupPanelSkin`).

/// Форма: произвольное содержимое, кнопки «отмена» и подтверждение.
///
/// Содержимое — **список** строк, а не одна: между ними форма сама ставит
/// зазор. Иначе каждое окно расставляет его вручную, а забывшее — слепляет
/// поля друг с другом; так и случилось с окном поиска.
class CommandDialogForm extends StatelessWidget {
  const CommandDialogForm({
    super.key,
    required this.children,
    required this.onCancel,
    required this.onSubmit,
    required this.submitLabel,
    this.error,
    this.busy = false,
  });

  final List<Widget> children;
  final VoidCallback onCancel;
  final VoidCallback onSubmit;
  final String submitLabel;
  final String? error;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return CommandDialogBody(
      actions: [
        FcButton(label: 'Cancel', onPressed: onCancel),
        FcButton(label: submitLabel, onPressed: busy ? null : onSubmit, primary: true),
      ],
      children: [...children, if (error != null) FcErrorText(message: error!)],
    );
  }
}

/// Подтверждение действия.
class CommandDialogConfirm extends StatelessWidget {
  const CommandDialogConfirm({
    super.key,
    required this.message,
    required this.confirmLabel,
    required this.onCancel,
    required this.onConfirm,
    this.error,
  });

  final String message;
  final String confirmLabel;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return CommandDialogBody(
      actions: [
        FcButton(label: 'Cancel', onPressed: onCancel),
        FcButton(label: confirmLabel, onPressed: onConfirm, primary: true),
      ],
      children: [
        Text(message, style: FcTheme.of(context).dialogTextStyle),
        if (error != null) FcErrorText(message: error!),
      ],
    );
  }
}

/// Ход выполнения с возможностью прервать.
///
/// Задаёт себе ширину — долю окна приложения: по ходу работы здесь меняются
/// имена файлов, и если бы окно облегало содержимое, оно «прыгало» бы на
/// каждом. Рамка окна ширину не назначает, она облегает то, что ей дали.
///
/// Устроено сверху вниз от частного к общему: этап работы, что именно
/// делается, текущий объект со своим объёмом и полосой, скорость и общий счёт
/// со своей полосой. Объект и итог — по три строки под одной подписью: так
/// видно, что объём и полоса относятся к своему счёту, а не к соседнему.
///
/// Счётчик объектов долгие операции досчитывают фоном, поэтому пока счёт не
/// закончен, к числу добавляется многоточие — иначе растущий «итог» выглядел бы
/// ошибкой.
class CommandDialogProgress extends StatelessWidget {
  const CommandDialogProgress({
    super.key,
    required this.message,
    this.onCancel,
    this.progress,
    this.processed = 0,
    this.total,
    this.totalIsFinal = true,
    this.bytes = 0,
    this.totalBytes,
    this.bytesPerSecond,
    this.remaining,
    this.canBackground = false,
    this.onBackground,
    this.itemName = '',
    this.itemProgress,
    this.itemBytes = 0,
    this.itemTotalBytes,
    this.stageLabel,
  });

  /// Который этап работы идёт; null — работа одноплечая, и строки не будет.
  final String? stageLabel;

  final String message;
  final double? progress;
  final int processed;
  final int? total;
  final bool totalIsFinal;

  /// Перенесённый объём и общий; null — объём не известен (удаление в корзину).
  final int bytes;
  final int? totalBytes;

  /// Скорость и оценка времени; null — считать пока не из чего.
  final double? bytesPerSecond;
  final Duration? remaining;

  /// Прервать работу; null — прерывать уже нечего, и кнопка приглушена.
  ///
  /// Живая кнопка «Cancel» у законченной работы хуже серой: отменять там нечего,
  /// и нажатие означало бы что-то другое, чем написано на кнопке.
  final VoidCallback? onCancel;

  /// Бывает ли у этой работы фон: без этого кнопки нет вовсе.
  final bool canBackground;

  /// Убрать окно и оставить работу идти; null — прятать сейчас нечего, и кнопка
  /// приглушена, но с места не девается.
  ///
  /// Разница с [canBackground] не придирка: ряд кнопок не должен переставляться
  /// ровно в тот момент, когда работа заканчивается, — иначе окно дёргается на
  /// прощание.
  final VoidCallback? onBackground;

  /// Что обрабатывается прямо сейчас и сколько его прошло.
  ///
  /// Имя можно давать с путём — окно покажет только последнюю часть.
  final String itemName;
  final double? itemProgress;
  final int itemBytes;
  final int? itemTotalBytes;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final counter = _counter;
    final size = _size;
    final speed = _speed;
    final itemSize = _itemSize;
    final fileName = _fileName;

    return SizedBox(
      width: MediaQuery.sizeOf(context).width * theme.metrics.dialogWidthFactor,
      child: CommandDialogBody(
        actions: [
          // «В фон» стоит слева от отмены: уводит работу с глаз, а не
          // прекращает её, — и путать эти две кнопки нельзя.
          if (canBackground || onBackground != null) FcButton(label: 'Background', onPressed: onBackground),
          FcButton(label: 'Cancel', onPressed: onCancel),
        ],
        children: [
          // Этап — первой строкой: он объясняет, почему счёт объектов уже
          // полон, а работа всё идёт.
          if (stageLabel case final stage?) CommandDialogField(label: 'Stage', child: _line(theme, stage)),
          CommandDialogField(label: 'Item', child: _line(theme, message)),
          // Про текущий объект — три строки под одной подписью: имя, объём,
          // своя полоса. Полоса не украшение: работа из тысячи мелких файлов и
          // работа из одного файла на четыре гигабайта в общем счёте выглядят
          // одинаково, а это ровно тот случай, когда кажется, что всё зависло.
          if (fileName != null)
            CommandDialogField.column(
              label: 'File',
              children: [
                _line(theme, fileName),
                if (itemSize != null) _line(theme, itemSize),
                if (itemProgress != null) FcProgressBar(value: itemProgress),
              ],
            ),
          if (speed != null) CommandDialogField(label: 'Speed', child: _line(theme, speed)),
          CommandDialogField.column(
            label: 'Total',
            children: [
              if (counter != null) _line(theme, counter),
              if (size != null) _line(theme, size),
              FcProgressBar(value: progress),
            ],
          ),
        ],
      ),
    );
  }

  /// Строка окна — всегда одна: длинное имя обрезается многоточием, а не
  /// переносится. Иначе окно росло бы вниз на каждом длинном пути.
  Widget _line(FcTheme theme, String text) =>
      Text(text, style: theme.dialogTextStyle, maxLines: 1, overflow: TextOverflow.ellipsis);

  /// Имя текущего объекта без пути.
  ///
  /// Путь внутри архива или внутри дерева длинный, а толку от него нет:
  /// обрабатывается то, что названо, а где оно лежит — видно по строке `Item`.
  String? get _fileName {
    if (itemName.isEmpty) {
      return null;
    }
    final trimmed = itemName.endsWith('/') ? itemName.substring(0, itemName.length - 1) : itemName;
    final cut = trimmed.lastIndexOf('/');
    final name = cut < 0 ? trimmed : trimmed.substring(cut + 1);
    return name.isEmpty ? itemName : name;
  }

  /// Объём текущего объекта: `1.2 MB of 4.0 GB`.
  String? get _itemSize {
    final size = itemTotalBytes;
    if (size == null || size <= 0) {
      return null;
    }
    return '${formatBytesLong(itemBytes)} of ${formatBytesLong(size)}';
  }

  String? get _counter {
    final count = total;
    if (count == null) {
      // Считать ещё не начали: показывать «0 из 0» бессмысленно.
      return processed == 0 ? null : '$processed';
    }
    return totalIsFinal ? '$processed of $count' : '$processed of $count…';
  }

  /// Объём: `12.4 MB of 700.1 MB`. Многоточие — то же, что у счётчика: общее
  /// ещё считают, и оно вырастет.
  String? get _size {
    final all = totalBytes;
    if (all == null || all <= 0) {
      return null;
    }
    final line = '${formatBytesLong(bytes)} of ${formatBytesLong(all)}';
    return totalIsFinal ? line : '$line…';
  }

  /// Скорость и сколько осталось: `12.4 MB/s, 00:42 left`.
  ///
  /// Оценка появляется не сразу: пока скорость не на чем считать, обещать
  /// время нельзя — соврать хуже, чем промолчать.
  String? get _speed {
    final speed = bytesPerSecond;
    if (speed == null || speed <= 0) {
      return null;
    }

    final left = remaining;
    final line = '${formatBytesLong(speed.round())}/s';
    return left == null ? line : '$line, ${formatDuration(left)} left';
  }
}

/// Вопрос по ходу работы: столько кнопок, сколько вариантов ответа.
class CommandDialogQuestion extends StatefulWidget {
  const CommandDialogQuestion({super.key, required this.request, required this.onAnswer, this.onTextChanged});

  final OperationRequest request;
  final void Function(OperationRequestOption option) onAnswer;

  /// Набранное сообщается по мере ввода — то же правило, что и у окон с
  /// параметрами: Enter обрабатывает ядро, и к моменту ответа текст уже должен
  /// лежать там, откуда его возьмут.
  final ValueChanged<String>? onTextChanged;

  @override
  State<CommandDialogQuestion> createState() => _CommandDialogQuestionState();
}

class _CommandDialogQuestionState extends State<CommandDialogQuestion> {
  final TextEditingController _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final label = request.inputLabel;

    return CommandDialogBody(
      actions: [
        for (final option in request.options)
          FcButton(
            label: option.label,
            onPressed: () => widget.onAnswer(option),
            primary: option == request.enterOption,
          ),
      ],
      children: [
        Text(request.message, style: FcTheme.of(context).dialogTextStyle),
        if (label != null)
          CommandDialogField(
            label: label,
            child: FcTextField(
              controller: _input,
              autofocus: true,
              obscureText: request.secret,
              onChanged: widget.onTextChanged,
              onSubmitted: (_) => widget.onAnswer(request.enterOption),
            ),
          ),
      ],
    );
  }
}

/// Содержимое окна: строки с полями и ряд кнопок под линией.
class CommandDialogBody extends StatelessWidget {
  const CommandDialogBody({super.key, required this.children, required this.actions});

  final List<Widget> children;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;
    final padding = EdgeInsets.symmetric(horizontal: metrics.dialogHorizontalPadding, vertical: metrics.dialogPadding);
    // Сверху отступ больше: содержимое отходит от полосы заголовка.
    final contentPadding = padding.copyWith(top: metrics.dialogContentTopPadding);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: contentPadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(height: metrics.dialogGap),
                children[i],
              ],
            ],
          ),
        ),
        CommandDialogActions(actions: actions),
      ],
    );
  }
}

/// Ряд кнопок внизу окна: линия, отступы и сами кнопки.
///
/// Общий для **всех** окон, и это не удобство, а необходимость: кнопка
/// (`FcButton`) — это `Container` с `alignment`, а такой контейнер под
/// ограниченной по ширине разметкой растягивается во всю её ширину. Ряд
/// с `mainAxisSize: min` даёт кнопкам неограниченную ширину, и каждая
/// получается по своей подписи.
///
/// Правило одно на все окна: **кнопки — по размеру подписи, одной строкой,
/// прижатой вправо** (`HorizontalLayout horizontalAlign="right"` в референсе).
/// Даже там, где кнопка одна.
class CommandDialogActions extends StatelessWidget {
  const CommandDialogActions({super.key, required this.actions});

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(height: metrics.dialogDividerHeight, color: theme.colors.dialogDivider),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: metrics.dialogHorizontalPadding, vertical: metrics.dialogPadding),
          // Ширина окна задана содержимым и от кнопок не зависит, поэтому пять
          // кнопок (вопрос о занятом имени) в узкое окно могут не помещаться.
          // Тогда `FittedBox` соразмерно уменьшает весь ряд — строка остаётся
          // одной, без переноса и без полосы переполнения.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < actions.length; i++) ...[if (i > 0) SizedBox(width: metrics.dialogGap), actions[i]],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Строка формы: подпись слева, содержимое справа (`SimpleFormItemSkin`).
///
/// Подпись — без двоеточия: она и так отличается от значения цветом, а
/// двоеточие в такой колонке только шумит.
class CommandDialogField extends StatelessWidget {
  const CommandDialogField({super.key, required this.label, required Widget child})
    : _child = child,
      children = const [];

  /// Несколько строк под одной подписью; подпись встаёт вровень с первой.
  ///
  /// Так связанное читается связанным: имя файла, его объём и его полоса —
  /// одно поле из трёх строк, а не три поля, из которых два безымянных.
  const CommandDialogField.column({super.key, required this.label, required this.children}) : _child = null;

  final String label;
  final List<Widget> children;
  final Widget? _child;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final single = _child;

    return Row(
      // Одну строку подпись держит по середине — как рядом с полем ввода;
      // столбец строк — по верхней, иначе она уедет в середину блока.
      crossAxisAlignment: single != null ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: theme.metrics.dialogLabelWidth,
          child: Text(label, textAlign: TextAlign.right, style: theme.dialogLabelStyle),
        ),
        SizedBox(width: theme.metrics.dialogGap),
        Expanded(child: single ?? _column(theme)),
      ],
    );
  }

  Widget _column(FcTheme theme) {
    final gap = theme.metrics.dialogLineGap;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[if (i > 0) SizedBox(height: gap), children[i]],
      ],
    );
  }
}

/// Кнопка окна команды — `RegularButtonSkin` и `DefaultButtonSkin` референса.
///
/// Отличаются они только цветом заливки: обычная `sea`, подтверждающая `blue1`.
/// Снизу вверх идёт лёгкое затемнение, нажатие затемняет кнопку целиком.
class FcButton extends StatefulWidget {
  const FcButton({super.key, required this.label, required this.onPressed, this.primary = false, this.focusNode});

  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  /// Узел фокуса — когда он нужен снаружи: окно хочет поставить фокус сюда.
  final FocusNode? focusNode;

  @override
  State<FcButton> createState() => _FcButtonState();
}

class _FcButtonState extends State<FcButton> {
  bool _pressed = false;
  bool _focused = false;

  bool get _enabled => widget.onPressed != null;

  /// `Space` и `Enter` нажимают кнопку, на которой стоит фокус.
  ///
  /// `Enter` берётся здесь, а не рамой окна: пока фокус не на кнопке, он
  /// по-прежнему уходит команде и подтверждает окно. Иначе человек, дотабившийся
  /// до «Cancel», нажатием `Enter` получил бы «Overwrite». Flutter отдаёт
  /// нажатие сперва узлу в фокусе, потом вверх по предкам, — этого и довольно.
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (!_enabled || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.space || event.logicalKey == LogicalKeyboardKey.enter) {
      widget.onPressed!.call();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;
    final colors = theme.colors;
    final radius = BorderRadius.circular(metrics.buttonRadius);

    // Кнопка облегает свою подпись, даже когда ей дают всю ширину окна:
    // содержимое окна выкладывается растягивающей колонкой, и без этого
    // одиночная кнопка растянулась бы во всю ширину. Ряд кнопок при этом
    // ничего не теряет — там ширина и так не навязывается.
    return Align(
      widthFactor: 1,
      heightFactor: 1,
      child: Focus(
        focusNode: widget.focusNode,
        // Выключенная кнопка обход пропускает сама собой — списка исключений
        // для этого не нужно.
        canRequestFocus: _enabled,
        skipTraversal: !_enabled,
        onKeyEvent: _handleKey,
        onFocusChange: (value) => setState(() => _focused = value),
        child: Opacity(
          opacity: _enabled ? 1 : 0.5,
          child: MouseRegion(
            cursor: _enabled ? SystemMouseCursors.click : MouseCursor.defer,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
              onTapUp: _enabled ? (_) => setState(() => _pressed = false) : null,
              onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
              onTap: widget.onPressed,
              child: Container(
                height: metrics.buttonHeight,
                padding: EdgeInsets.symmetric(horizontal: metrics.buttonHorizontalPadding),
                decoration: BoxDecoration(
                  color: widget.primary ? colors.buttonPrimaryBackground : colors.buttonBackground,
                  border: Border.all(
                    color: _focused ? colors.focusRing : colors.buttonBorder,
                    width: metrics.strokeWidth * (_focused ? 2 : 1),
                  ),
                  borderRadius: radius,
                  // Тень под кнопкой: она отделяет её от фона окна.
                  boxShadow: [
                    BoxShadow(
                      color: colors.shadow,
                      offset: Offset(0, metrics.buttonShadowOffset),
                      blurRadius: metrics.buttonShadowBlur,
                    ),
                  ],
                ),
                // Заливка ровная, без градиента; затемняется только нажатая кнопка.
                foregroundDecoration:
                    _pressed ? BoxDecoration(color: colors.buttonPressed, borderRadius: radius) : null,
                // Center с множителями, а не `alignment` у Container: с ним кнопка
                // заняла бы всю предложенную ширину, а нужна ширина подписи.
                child: Center(widthFactor: 1, heightFactor: 1, child: Text(widget.label, style: theme.buttonStyle)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Поле ввода — `TextInputBorderedSkin` референса.
///
/// Выключенное поле остаётся полем: то, что менять нельзя, показывается в такой
/// же рамке, только приглушённой (`alpha.disabled = 0.5` в скине референса) —
/// так форма читается как форма, а не как текст вперемешку с полями.
class FcTextField extends StatefulWidget {
  const FcTextField({
    super.key,
    required this.controller,
    this.hintText,
    this.autofocus = false,
    this.enabled = true,
    this.obscureText = false,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
  });

  /// Узел фокуса — когда он нужен снаружи.
  final FocusNode? focusNode;

  final TextEditingController controller;
  final String? hintText;
  final bool autofocus;

  /// Набранное не показывать: пароль.
  final bool obscureText;

  /// Выключенное поле не принимает ни ввод, ни фокус: обходя окно клавишей
  /// табуляции, на нём останавливаться незачем.
  final bool enabled;

  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<FcTextField> createState() => _FcTextFieldState();
}

class _FcTextFieldState extends State<FcTextField> {
  /// Свой узел — только если снаружи не дали: поле должно знать, в фокусе оно
  /// или нет, а `TextField` об этом не рассказывает.
  FocusNode? _own;

  FocusNode get _node => widget.focusNode ?? (_own ??= FocusNode(debugLabel: 'FcTextField'));

  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(FcTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_onFocusChanged);
      _node.addListener(_onFocusChanged);
      _onFocusChanged();
    }
  }

  void _onFocusChanged() {
    if (mounted && _focused != _node.hasFocus) {
      setState(() => _focused = _node.hasFocus);
    }
  }

  @override
  void dispose() {
    _node.removeListener(_onFocusChanged);
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;
    final colors = theme.colors;
    final enabled = widget.enabled;

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Container(
        height: metrics.inputHeight,
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(horizontal: metrics.inputHorizontalPadding),
        decoration: BoxDecoration(
          color: colors.inputBackground,
          border: Border.all(
            color: _focused ? colors.focusRing : colors.inputBorder,
            width: metrics.strokeWidth * (_focused ? 2 : 1),
          ),
          borderRadius: BorderRadius.circular(metrics.inputRadius),
        ),
        child: TextField(
          controller: widget.controller,
          focusNode: _node,
          autofocus: widget.autofocus,
          enabled: enabled,
          obscureText: widget.obscureText,
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
          style: theme.inputStyle,
          cursorColor: colors.inputText,
          decoration: InputDecoration(
            isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            hintText: widget.hintText,
            hintStyle: theme.inputStyle.copyWith(color: colors.inputHint),
          ),
        ),
      ),
    );
  }
}

/// Полоса хода работы — `ProgressBar.mxml`: обводка и заливка одного цвета,
/// заливка вписана внутрь с небольшим отступом.
class FcProgressBar extends StatelessWidget {
  const FcProgressBar({super.key, this.value});

  /// 0…1; null — доля неизвестна, полоса пуста.
  final double? value;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;

    return Container(
      height: metrics.progressHeight,
      decoration: BoxDecoration(
        border: Border.all(color: theme.colors.progress, width: metrics.strokeWidth),
        borderRadius: BorderRadius.circular(metrics.progressHeight / 2),
      ),
      padding: EdgeInsets.all(metrics.progressInset),
      // Заполненная часть отмеряется долями `Row`, а не шириной по замеру
      // родителя: окно команды меряет себя по содержимому (`IntrinsicWidth`),
      // а `LayoutBuilder` такого измерения не переживает вовсе, у
      // `FractionallySizedBox` же при нулевой доле внутренняя ширина
      // обращается в бесконечность.
      // Заливка тянется на всю высоту полосы: у пустого `DecoratedBox` своей
      // высоты нет, и по умолчанию `Row` оставил бы от него нулевую полоску.
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: _parts(theme, metrics)),
    );
  }

  List<Widget> _parts(FcTheme theme, FcMetrics metrics) {
    const total = 1000;
    final filled = ((value ?? 0).clamp(0.0, 1.0) * total).round();

    return [
      if (filled > 0)
        Expanded(
          flex: filled,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colors.progress,
              borderRadius: BorderRadius.circular(metrics.progressHeight / 2 - metrics.progressInset),
            ),
          ),
        ),
      if (filled < total) Expanded(flex: total - filled, child: const SizedBox.shrink()),
    ];
  }
}

/// Сообщение об ошибке в окне команды.
class FcErrorText extends StatelessWidget {
  const FcErrorText({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    return Text(message, style: theme.dialogTextStyle.copyWith(color: theme.colors.error));
  }
}
