import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'fc_theme.dart';

/// Готовые куски содержимого окна команды.
///
/// Рамку и заголовок рисует ядро, а внутренности — команда. Чтобы окна разных
/// команд выглядели одинаково, типовые случаи собраны здесь: форма с полем
/// ввода, подтверждение, ход выполнения и вопрос по ходу работы.
///
/// Вид взят у референса: содержимое с полями `padding="20" paddingLeft="40"`,
/// под ним ряд кнопок, прижатых вправо (`TitledPopupPanelSkin`).
///
/// Линии над кнопками, которая была в референсе, у нас нет: на тёмном фоне она
/// вышла едва различимой — не граница, а грязь на стекле. Отделяет ряд от
/// содержимого воздух, и его довольно.

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

  /// Строки формы — описаниями, а не виджетами: столбец подписей один на всю
  /// форму, и разложить её может только тот, кто видит их все сразу.
  final List<CommandDialogField> children;
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
      children: [...children, if (error != null) CommandDialogField.wide(child: FcErrorText(message: error!))],
    );
  }
}

/// Подтверждение действия.
///
/// Утвердительных ответов бывает два: у выхода из редактора с несохранённым это
/// «сохранить и выйти» и «выйти, потеряв правки». Второй объявляется через
/// [alternativeLabel] и встаёт **между** отменой и основной кнопкой: слева
/// направо ряд идёт от самого безобидного ответа к самому охотному, и `Enter`
/// достаётся тому, что стоит последним.
class CommandDialogConfirm extends StatelessWidget {
  const CommandDialogConfirm({
    super.key,
    required this.message,
    required this.confirmLabel,
    required this.onCancel,
    required this.onConfirm,
    this.alternativeLabel,
    this.onAlternative,
    this.error,
    this.busy = false,
  }) : assert((alternativeLabel == null) == (onAlternative == null), 'Вторая кнопка — это подпись и обработчик разом');

  final String message;
  final String confirmLabel;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  /// Второй утвердительный ответ; пусто — окно остаётся двухкнопочным.
  final String? alternativeLabel;
  final VoidCallback? onAlternative;

  final String? error;

  /// Ответ принят, и он оказался долгим: кнопки приглушены, пока идёт работа.
  ///
  /// Отмена при этом живой не остаётся: у окна, которое уже пишет файл, «не
  /// надо» означало бы обрыв записи на середине, а обрывать её нечем.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final alternative = alternativeLabel;

    return CommandDialogBody(
      actions: [
        FcButton(label: 'Cancel', onPressed: busy ? null : onCancel),
        if (alternative != null) FcButton(label: alternative, onPressed: busy ? null : onAlternative),
        FcButton(label: confirmLabel, onPressed: busy ? null : onConfirm, primary: true),
      ],
      children: [
        CommandDialogField.wide(child: Text(message, style: FcTheme.of(context).dialogTextStyle)),
        if (error != null) CommandDialogField.wide(child: FcErrorText(message: error!)),
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
        CommandDialogField.wide(child: Text(request.message, style: FcTheme.of(context).dialogTextStyle)),
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

/// Содержимое окна: строки с полями и ряд кнопок под ними.
class CommandDialogBody extends StatelessWidget {
  const CommandDialogBody({super.key, required this.children, required this.actions});

  /// Строки формы — описаниями, а не виджетами: столбец подписей один на всю
  /// форму, и разложить её может только тот, кто видит их все сразу.
  final List<CommandDialogField> children;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;
    // Поля по краям ставит сама форма: строка `bleed` выходит за них к краям
    // окна, а изнутри общего `Padding` выйти нечем. Сверху отступ больше —
    // содержимое отходит от полосы заголовка.
    final contentPadding = EdgeInsets.only(top: metrics.dialogContentTopPadding, bottom: metrics.dialogPadding);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: contentPadding,
          child: FcForm(rows: children, horizontalPadding: metrics.dialogHorizontalPadding),
        ),
        CommandDialogActions(actions: actions),
      ],
    );
  }
}

/// Ряд кнопок внизу окна: отступы и сами кнопки.
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
/// Сколько места содержимому окна дозволено занять.
///
/// Одно правило на все окна: рама облегает содержимое, поэтому предел ставит
/// само содержимое, а не рама. Без предела высоты прокрутка внутри окна не
/// работает вовсе — `Flexible` получает бесконечность и не ограничивает
/// ничего, а колонка вылезает за экран.
///
/// Полоса заголовка вычитается: её рисует рама, а поля считаются для окна
/// целиком. У окна без заголовка полосы нет вовсе ([titled]) — и вычитать
/// нечего: место, отведённое под то, чего не рисуют, окно бы просто потеряло.
BoxConstraints dialogContentLimits(BuildContext context, {bool titled = true}) {
  final metrics = FcTheme.of(context).metrics;
  final screen = MediaQuery.sizeOf(context);
  final inset = metrics.dialogScreenInset;
  // Доля окна, а не поля по краям: поля дают предел, зависящий от того, как
  // далеко отодвинуты края, — и на широком экране окно растягивалось бы во всю
  // ширину, оставляя от панелей две узкие полоски.
  final width = screen.width * metrics.dialogMaxScreenFactor;
  final height = screen.height - inset * 2 - (titled ? metrics.dialogTitleHeight : 0);

  return BoxConstraints(maxWidth: width < 0 ? 0 : width, maxHeight: height < 0 ? 0 : height);
}

/// Ширина самой широкой подписи — но не шире предела из темы.
///
/// Нужна тем, кто собирает **несколько** форм, которые должны выглядеть одной:
/// каждая таблица меряет только свои строки, а столбец у них обязан быть общий.
///
/// Меряется настоящим набором текста, а не длиной строки: `Compression` и
/// `WWWWWWWWWWW` — разные ширины при одинаковой длине, а подписи бывают и
/// нелатинские. И тем же стилем, каким текст нарисуют: `Text` смешивает
/// переданный стиль с наследуемым, и без этого замер расходится с
/// действительностью.
double widestLabel(BuildContext context, Iterable<String> labels) {
  final theme = FcTheme.of(context);
  final scaler = MediaQuery.textScalerOf(context);
  final style = DefaultTextStyle.of(context).style.merge(theme.dialogLabelStyle);
  var widest = 0.0;

  for (final label in labels) {
    if (label.isEmpty) {
      continue;
    }
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    // `maxIntrinsicWidth`, а не `width`: именно её берёт раскладка, когда
    // спрашивает, сколько тексту нужно. `width` округляется иначе, и подпись не
    // влезала в собственную ширину — переносилась на вторую строку.
    final needed = painter.maxIntrinsicWidth;
    widest = widest > needed ? widest : needed;
    painter.dispose();
  }

  // Округление вверх: доли точки в раскладке дают дрожание на границе, а
  // выиграть на них нечего.
  return widest.ceilToDouble().clamp(0, theme.metrics.dialogLabelMaxWidth);
}

/// Как отбивается содержимое окна от его краёв.
///
/// Одно правило на все окна — рядом с [dialogContentLimits] и по той же
/// причине: два окна, отбитые по-разному, выглядят как недосмотр, а сверять их
/// глазами приходится каждый раз заново.
///
/// Сверху больше остальных: содержимое отходит от полосы заголовка.
EdgeInsets dialogContentPadding(BuildContext context) {
  final metrics = FcTheme.of(context).metrics;

  return EdgeInsets.only(
    left: metrics.dialogHorizontalPadding,
    right: metrics.dialogHorizontalPadding,
    top: metrics.dialogContentTopPadding,
    bottom: metrics.dialogPadding,
  );
}

/// Где начинается текст внутри поля ввода, считая от края окна.
///
/// Нужна списку под полем: его строка выбора идёт во всю ширину окна, а текст в
/// ней обязан стоять ровно под набранным — иначе список выглядит съехавшим
/// относительно того самого поля, которое он дополняет.
///
/// Складывается из поля окна, рамки поля ввода и его собственного отступа —
/// ровно из того, что стоит слева от текста в [FcTextField].
double dialogInputTextInset(BuildContext context, {double labelWidth = 0}) {
  final metrics = FcTheme.of(context).metrics;
  // Подпись слева — если форма поставила поле в столбец значений: там текст
  // начинается за подписью и зазором между столбцами.
  final label = labelWidth > 0 ? labelWidth + metrics.dialogGap : 0.0;

  return metrics.dialogHorizontalPadding + label + metrics.strokeWidth + metrics.inputHorizontalPadding;
}

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
/// **Описание, а не виджет.** Столбец подписей должен быть один на всю форму и
/// шириной по самой широкой из них — а это знает только тот, кто видит все
/// строки сразу. Виджет-строка знала бы лишь свою подпись, и столбец пришлось
/// бы задавать числом, как раньше: короткая форма зияла пустотой слева, а
/// длинная подпись переносилась в две строки.
///
/// Подпись — без двоеточия: она и так отличается от значения цветом, а
/// двоеточие в такой колонке только шумит.
class CommandDialogField {
  const CommandDialogField({required this.label, required Widget child})
    : _child = child,
      children = const [],
      bleeds = false;

  /// Несколько строк под одной подписью; подпись встаёт вровень с первой.
  ///
  /// Так связанное читается связанным: имя файла, его объём и его полоса —
  /// одно поле из трёх строк, а не три поля, из которых два безымянных.
  const CommandDialogField.column({required this.label, required this.children}) : _child = null, bleeds = false;

  /// Строка без подписи — во всю ширину столбца значений.
  ///
  /// Флаг, полоса хода работы, сообщение об ошибке: подписи слева у них нет, а
  /// вставать они должны вровень с остальными значениями, а не с их подписями.
  const CommandDialogField.wide({required Widget child})
    : label = '',
      _child = child,
      children = const [],
      bleeds = false;

  /// Строка во всю ширину **окна** — мимо полей формы.
  ///
  /// Список под полем ввода: его подсветка — это строка выбора, а строка выбора
  /// обязана доходить до краёв окна, иначе она читается не как «эта строка», а
  /// как «эта плитка». Само содержимое строки при этом отбито внутри — под
  /// текстом поля ввода ([dialogInputTextInset]).
  const CommandDialogField.bleed({required Widget child})
    : label = '',
      _child = child,
      children = const [],
      bleeds = true;

  final String label;

  /// Строка выходит за поля формы к самым краям окна.
  final bool bleeds;
  final List<Widget> children;
  final Widget? _child;

  /// Содержимое строки — одно или столбцом.
  Widget content(FcTheme theme) {
    final single = _child;
    if (single != null) {
      return single;
    }

    final gap = theme.metrics.dialogLineGap;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[if (i > 0) SizedBox(height: gap), children[i]],
      ],
    );
  }

  /// Строка без подписи: идёт мимо столбцов, во всю ширину формы.
  bool get isWide => label.isEmpty;

  /// Одну строку подпись держит по середине — как рядом с полем ввода; столбец
  /// строк — по верхней, иначе она уедет в середину блока.
  TableCellVerticalAlignment get alignment =>
      _child != null ? TableCellVerticalAlignment.middle : TableCellVerticalAlignment.top;
}

/// Форма: пары «подпись — значение», выровненные по одному столбцу.
///
/// Столбец подписей — по самой широкой из них, но не шире предела темы
/// ([FcMetrics.dialogLabelMaxWidth]): без предела одна длинная подпись съедает
/// форму, а значения ужимаются в остаток и переносятся по слову.
///
/// Строки «во всю ширину» ([CommandDialogField.wide]) идут **мимо столбцов** —
/// флагу, полосе хода работы и сообщению об ошибке подпись слева не нужна, а
/// ужиматься в столбец значений им незачем. У `Table` в Flutter объединения
/// ячеек нет вовсе, поэтому такая строка выходит из таблицы: форма — это
/// череда таблиц и широких строк между ними. Выравнивание от этого не
/// страдает, потому что мера столбца общая и посчитана заранее.
///
/// Начинаются они всё же **там, где значения**, а не у самого края: в
/// референсе флаг стоит под полем ввода, а не под его подписью. Слева им
/// отводится ровно столбец подписей с зазором — и тогда флаг читается как
/// продолжение поля, к которому относится. Просвет вокруг такой строки
/// отдельный ([FcMetrics.dialogWideRowGap]) и больше обычного: она стоит под
/// полями, а не в их ряду. **С обеих сторон**, а не только сверху: отбитая
/// лишь сверху, она прижимается к строке под собой и читается как её часть.
class FcForm extends StatelessWidget {
  const FcForm({super.key, required this.rows, this.labelWidth, this.horizontalPadding = 0});

  final List<CommandDialogField> rows;

  /// Ширина столбца подписей, если её задают снаружи.
  ///
  /// Нужна там, где форм несколько, а столбец должен быть один: разделы окна
  /// настроек лежат порознь (между ними заголовки), но читаются как одна
  /// форма. Пусто — форма меряет свои подписи сама.
  final double? labelWidth;

  /// Поля по краям — те самые, что отбивают содержимое от рамы окна.
  ///
  /// Ставит их **форма**, а не тот, кто её показывает: строка `bleed` обязана
  /// выйти за них к самым краям окна, а изнутри общего `Padding` выйти нечем.
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;
    final width = labelWidth ?? widestLabel(context, [for (final row in rows) row.label]);

    final parts = <Widget>[];
    // Просвет **перед** каждой частью; у первой его нет.
    final gaps = <double>[];
    var run = <CommandDialogField>[];
    var lastWide = false;

    Widget inset(Widget part) =>
        horizontalPadding == 0
            ? part
            : Padding(padding: EdgeInsets.symmetric(horizontal: horizontalPadding), child: part);

    /// Просвет между соседями — по тому из них, кому нужен больший.
    ///
    /// Широкая строка отбита с **обеих** сторон, а не только сверху: она стоит
    /// под полями, а не в их ряду, и отделять её от того, что ниже, нужно ровно
    /// так же. С просветом только сверху флажок прижимался к строке под собой и
    /// читался как её часть.
    void add(Widget part, {required bool wide}) {
      gaps.add(parts.isEmpty ? 0 : (wide || lastWide ? metrics.dialogWideRowGap : metrics.dialogGap));
      parts.add(part);
      lastWide = wide;
    }

    void flush() {
      if (run.isEmpty) {
        return;
      }
      add(inset(_table(theme, width, run)), wide: false);
      run = [];
    }

    for (final row in rows) {
      if (row.isWide) {
        flush();
        // Строка без подписи начинается там же, где значения: под полем ввода,
        // а не под его подписью. Кроме той, что выходит к самым краям окна, —
        // ей поля не отводятся вовсе.
        //
        // **Столбца подписей может не быть вовсе** — окно поиска целиком собрано
        // из широких строк. Тогда и отступать не от чего: отведённый под пустой
        // столбец зазор сдвигал бы всё содержимое вправо, и поле слева
        // оказывалось шире правого ровно на него. Окно от этого выглядело
        // косым, а причина не находилась ни в нём самом, ни в теме.
        final indent = width == 0 ? 0.0 : width + metrics.dialogGap;
        final content =
            row.bleeds
                ? row.content(theme)
                : inset(
                  indent == 0
                      ? row.content(theme)
                      : Padding(padding: EdgeInsets.only(left: indent), child: row.content(theme)),
                );
        add(content, wide: true);
        continue;
      }
      run.add(row);
    }
    flush();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < parts.length; i++) ...[if (gaps[i] > 0) SizedBox(height: gaps[i]), parts[i]],
      ],
    );
  }

  Widget _table(FcTheme theme, double width, List<CommandDialogField> rows) {
    final metrics = theme.metrics;

    return Table(
      // Значение меряется по себе **и** забирает остаток: по себе — чтобы окно
      // выросло под длинное поле (рама облегает содержимое, а `FlexColumnWidth`
      // в замере отвечает нулём и ширины окну не прибавляет); остаток — чтобы
      // на широком окне поле занимало всё место.
      columnWidths: {0: FixedColumnWidth(width), 1: const IntrinsicColumnWidth(flex: 1)},
      children: [
        for (var i = 0; i < rows.length; i++)
          TableRow(
            children: [
              TableCell(
                verticalAlignment: rows[i].alignment,
                child: Padding(
                  // Зазор между строками ставит форма: строки о соседях не
                  // знают, а собранные из разных мест — тем более.
                  //
                  // Поля у подписи только снизу: столбец шириной ровно в
                  // подпись, и отняв у него на зазор, мы отняли бы у текста —
                  // он переносился на вторую строку. Зазор между столбцами —
                  // слева у значения.
                  padding: EdgeInsets.only(bottom: i == rows.length - 1 ? 0 : metrics.dialogGap),
                  child: Text(rows[i].label, textAlign: TextAlign.right, style: theme.dialogLabelStyle),
                ),
              ),
              TableCell(
                verticalAlignment: rows[i].alignment,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: metrics.dialogGap,
                    bottom: i == rows.length - 1 ? 0 : metrics.dialogGap,
                  ),
                  child: rows[i].content(theme),
                ),
              ),
            ],
          ),
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
                  border: Border.all(color: colors.buttonBorder, width: metrics.strokeWidth),
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
                // Обводка фокуса — **поверх**, а не рамкой: рамка входит в
                // размер, и кнопка от неё раздавалась бы на глазах — тронул
                // `Tab`ом, и ряд поехал. Поверх — значит по тем же границам,
                // что и были.
                //
                // Слой стоит **всегда**, а не появляется вместе с фокусом:
                // `Container` от появления `foregroundDecoration` меняет
                // строение дерева, и всё, что под ним, пересоздаётся. Для поля
                // ввода это стоило бы связи с клавиатурой — набранное уходило бы
                // в никуда. Невидимость выражается прозрачным цветом.
                foregroundDecoration: BoxDecoration(
                  color: _pressed ? colors.buttonPressed : null,
                  border: Border.all(
                    color: _focused ? colors.focusRing : const Color(0x00000000),
                    width: metrics.focusRingWidth,
                  ),
                  borderRadius: radius,
                ),
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
    this.readOnly = false,
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

  /// Поле показывает, но не принимает ввод — и **фокус при этом держит**.
  ///
  /// Не то же, что [enabled]: выключенное отдаёт фокус, и вернуть его потом
  /// нечем — `autofocus` срабатывает один раз. Поэтому окно, которое запретило
  /// правку на время работы, после отмены снова принимает ввод само, без
  /// уговоров.
  final bool readOnly;

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

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;
    final colors = theme.colors;
    final enabled = widget.enabled;

    // Перестраивается **обводка**, а не поле: `ListenableBuilder` держит
    // `TextField` тем же самым объектом (он приходит `child`), а трогает только
    // рамку вокруг него.
    //
    // Иначе поле пересобиралось бы на каждую смену фокуса — и роняло бы связь с
    // вводом ровно в тот момент, когда её устанавливают: набранное уходило в
    // никуда. Проверяется это тестом про вопрос с паролем.
    return ListenableBuilder(
      listenable: _node,
      child: TextField(
        controller: widget.controller,
        focusNode: _node,
        autofocus: widget.autofocus,
        enabled: enabled,
        readOnly: widget.readOnly,
        obscureText: widget.obscureText,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        style: theme.inputStyle,
        cursorColor: colors.inputText,
        // Толщина и скругление — общие: курсор в окне, в командной строке и в
        // нарисованных полях должен выглядеть одинаково.
        cursorWidth: metrics.caretWidth,
        cursorRadius: Radius.circular(metrics.caretRadius),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
          hintText: widget.hintText,
          hintStyle: theme.inputStyle.copyWith(color: colors.inputHint),
        ),
      ),
      builder: (context, child) {
        return Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Container(
            height: metrics.inputHeight,
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(horizontal: metrics.inputHorizontalPadding),
            decoration: BoxDecoration(
              color: colors.inputBackground,
              border: Border.all(color: colors.inputBorder, width: metrics.strokeWidth),
              borderRadius: BorderRadius.circular(metrics.inputRadius),
            ),
            // Поверх, а не рамкой: рамка входит в размер, и поле от неё сдвинуло
            // бы и подпись рядом, и ширину всего окна.
            // Слой стоит всегда: `Container` от его появления пересобрал бы
            // поле, а с ним и связь с вводом. Невидимость — прозрачным цветом.
            foregroundDecoration: BoxDecoration(
              border: Border.all(
                color: _node.hasFocus ? colors.focusRing : const Color(0x00000000),
                width: metrics.focusRingWidth,
              ),
              borderRadius: BorderRadius.circular(metrics.inputRadius),
            ),
            child: child,
          ),
        );
      },
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
