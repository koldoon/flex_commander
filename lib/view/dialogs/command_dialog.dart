import 'package:flutter/material.dart';

import '../../model/async/operation_request.dart';
import '../format/duration_format.dart';
import '../format/size_format.dart';
import '../theme/app_metrics.dart';
import '../theme/app_theme.dart';

/// Готовые куски содержимого окна команды.
///
/// Рамку и заголовок рисует ядро, а внутренности — команда. Чтобы окна разных
/// команд выглядели одинаково, типовые случаи собраны здесь: форма с полем
/// ввода, подтверждение, ход выполнения и вопрос по ходу работы.
///
/// Вид взят у референса: содержимое с полями `padding="20" paddingLeft="40"`,
/// под ним линия и ряд кнопок, прижатых вправо (`TitledPopupPanelSkin`).

/// Форма: произвольное содержимое, кнопки «отмена» и подтверждение.
class CommandDialogForm extends StatelessWidget {
  const CommandDialogForm({
    super.key,
    required this.child,
    required this.onCancel,
    required this.onSubmit,
    required this.submitLabel,
    this.error,
    this.busy = false,
  });

  final Widget child;
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
      children: [child, if (error != null) _CommandDialogError(message: error!)],
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
        if (error != null) _CommandDialogError(message: error!),
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
/// Кроме полосы показывает счётчик объектов: сколько обработано из скольких.
/// Общее количество долгие операции считают фоном, поэтому пока счёт не
/// закончен, к числу добавляется многоточие — иначе растущий «итог» выглядел бы
/// ошибкой.
class CommandDialogProgress extends StatelessWidget {
  const CommandDialogProgress({
    super.key,
    required this.message,
    required this.onCancel,
    this.progress,
    this.processed = 0,
    this.total,
    this.totalIsFinal = true,
    this.bytes = 0,
    this.totalBytes,
    this.bytesPerSecond,
    this.remaining,
  });

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

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final counter = _counter;
    final size = _size;
    final speed = _speed;

    return SizedBox(
      width: MediaQuery.sizeOf(context).width * theme.metrics.dialogWidthFactor,
      child: CommandDialogBody(
        actions: [FcButton(label: 'Cancel', onPressed: onCancel)],
        children: [
          CommandDialogField(
            label: 'Item:',
            child: Text(message, style: theme.dialogTextStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (counter != null)
            CommandDialogField(label: 'Processed:', child: Text(counter, style: theme.dialogTextStyle)),
          if (size != null) CommandDialogField(label: 'Size:', child: Text(size, style: theme.dialogTextStyle)),
          if (speed != null) CommandDialogField(label: 'Speed:', child: Text(speed, style: theme.dialogTextStyle)),
          CommandDialogField(label: 'Progress:', child: FcProgressBar(value: progress)),
        ],
      ),
    );
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
class CommandDialogQuestion extends StatelessWidget {
  const CommandDialogQuestion({super.key, required this.message, required this.options, required this.onAnswer});

  final String message;
  final List<OperationOption> options;
  final void Function(OperationOption option) onAnswer;

  @override
  Widget build(BuildContext context) {
    return CommandDialogBody(
      actions: [
        for (final option in options)
          FcButton(label: option.label, onPressed: () => onAnswer(option), primary: option == options.first),
      ],
      children: [Text(message, style: FcTheme.of(context).dialogTextStyle)],
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
class CommandDialogField extends StatelessWidget {
  const CommandDialogField({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);

    return Row(
      children: [
        SizedBox(
          width: theme.metrics.dialogLabelWidth,
          child: Text(label, textAlign: TextAlign.right, style: theme.dialogLabelStyle),
        ),
        SizedBox(width: theme.metrics.dialogGap),
        Expanded(child: child),
      ],
    );
  }
}

/// Кнопка окна команды — `RegularButtonSkin` и `DefaultButtonSkin` референса.
///
/// Отличаются они только цветом заливки: обычная `sea`, подтверждающая `blue1`.
/// Снизу вверх идёт лёгкое затемнение, нажатие затемняет кнопку целиком.
class FcButton extends StatefulWidget {
  const FcButton({super.key, required this.label, required this.onPressed, this.primary = false});

  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  State<FcButton> createState() => _FcButtonState();
}

class _FcButtonState extends State<FcButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;
    final colors = theme.colors;
    final radius = BorderRadius.circular(metrics.buttonRadius);

    return Opacity(
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
            alignment: Alignment.center,
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
            foregroundDecoration: _pressed ? BoxDecoration(color: colors.buttonPressed, borderRadius: radius) : null,
            child: Text(widget.label, style: theme.buttonStyle),
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
class FcTextField extends StatelessWidget {
  const FcTextField({
    super.key,
    required this.controller,
    this.hintText,
    this.autofocus = false,
    this.enabled = true,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String? hintText;
  final bool autofocus;

  /// Выключенное поле не принимает ни ввод, ни фокус: обходя окно клавишей
  /// табуляции, на нём останавливаться незачем.
  final bool enabled;

  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;
    final colors = theme.colors;

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
        child: TextField(
          controller: controller,
          autofocus: autofocus,
          enabled: enabled,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          style: theme.inputStyle,
          cursorColor: colors.inputText,
          decoration: InputDecoration(
            isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            hintText: hintText,
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

class _CommandDialogError extends StatelessWidget {
  const _CommandDialogError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    return Text(message, style: theme.dialogTextStyle.copyWith(color: theme.colors.error));
  }
}
