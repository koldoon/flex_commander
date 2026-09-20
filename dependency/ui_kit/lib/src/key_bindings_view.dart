import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_scope.dart';
import 'command_dialog.dart';
import 'dialog_body.dart';
import 'fc_theme.dart';
import 'pick_list.dart';

/// Строка окна настройки клавиш — **привязка**, а не команда
/// (`docs/spec/key-bindings.md`, §2).
class KeyBindingItem {
  const KeyBindingItem({
    required this.id,
    required this.command,
    required this.label,
    required this.keys,
    required this.defaultKeys,
    this.description = '',
    this.owner = '',
    this.details = '',
    this.cannotEdit = '',
  });

  /// Чем строка отзовётся: команда и её прежняя комбинация.
  ///
  /// Составной, потому что составная и сама привязка: у одной команды их
  /// бывает несколько, и различать их нечем, кроме клавиши, с которой они
  /// объявлены.
  final String id;

  /// Идентификатор команды: `file.copy`.
  ///
  /// В строке его не видно, а искать по нему можно — как по названию модуля.
  /// Так находят **ту самую** привязку там, где названия повторяются: «Copy»
  /// есть и у файловых операций, и у просмотрщика.
  final String command;

  final String label;

  /// Что команда делает — рядом с названием.
  final String description;

  /// Название модуля: искать по нему можно, читать в строке нечего.
  final String owner;

  /// Чем эта привязка отличается от соседних у той же команды: значения, с
  /// которыми команда запускается (`Cmd-1` — таблица, `Cmd-2` — краткий).
  final String details;

  /// Действующая комбинация; пусто — клавиши нет.
  final String keys;

  /// Комбинация, с которой привязку объявил модуль.
  final String defaultKeys;

  /// Почему переназначить нельзя; пусто — можно.
  ///
  /// Словами, а не флагом: отказ без причины неотличим от поломки, а причины
  /// две — привязка «любой символ» и команда, у которой клавиши нет вовсе
  /// (`docs/spec/key-bindings.md`, §9).
  final String cannotEdit;

  bool get editable => cannotEdit.isEmpty;

  /// Стоит ли умолчание.
  bool get isDefault => keys == defaultKeys;

  FcPickRow row(String captured) => FcPickRow(
    id: id,
    title: label,
    subtitle: details.isEmpty ? description : '$description — $details',
    // Справа — то, чем команда вызывается: ради этого окно и открывают.
    trailing: captured.isEmpty ? (keys.isEmpty ? '—' : keys) : captured,
    keywords: [command, if (owner.isNotEmpty) owner, if (keys.isNotEmpty) keys],
  );
}

/// Окно настройки клавиш: список привязок, назначение нажатием.
///
/// Список и отбор — общие с палитрой команд ([FcPickList]); своё здесь одно:
/// `Enter` начинает **захват**, а не запускает команду.
///
/// Захват — состояние окна, а не поле ввода. Спорить с разбором привязок ему не
/// приходится: пока открыто окно команды, ранний обработчик приложения отходит
/// в сторону целиком, и нажатия достаются дереву фокуса
/// (`docs/spec/key-bindings.md`, §6).
class FcKeyBindings extends StatefulWidget {
  const FcKeyBindings({
    super.key,
    required this.items,
    required this.onAssign,
    required this.onClear,
    required this.onReset,
    required this.onResetAll,
    required this.occupiedBy,
  });

  final List<KeyBindingItem> items;

  /// Назначить привязке комбинацию.
  final void Function(String id, String keys) onAssign;

  /// Снять клавишу: привязка остаётся, нажатия у неё нет.
  final void Function(String id) onClear;

  /// Вернуть умолчание — этой привязке и всем сразу.
  final void Function(String id) onReset;
  final void Function() onResetAll;

  /// Кто держит эту комбинацию **в том же месте**; null — никто, и спорить не
  /// о чем (`docs/spec/key-bindings.md`, §3).
  final String? Function(String id, String keys) occupiedBy;

  @override
  State<FcKeyBindings> createState() => _FcKeyBindingsState();
}

class _FcKeyBindingsState extends State<FcKeyBindings> {
  /// Клавиши самого окна — **разобранные**, а не строками.
  ///
  /// `Cmd` вне macOS сворачивается в `Ctrl`, и сравнение с написанным
  /// `'Cmd-R'` там не совпало бы никогда (`KeyCombination.parse`).
  static final KeyCombination _enter = KeyCombination.parse('Enter');
  static final KeyCombination _escape = KeyCombination.parse('Esc');
  static final KeyCombination _clear = KeyCombination.parse('Bsp');
  static final KeyCombination _default = KeyCombination.parse('Cmd-R');

  final TextEditingController _query = TextEditingController();

  /// Клавиши списка разбираются на самом поле ввода — как в палитре: иначе
  /// стрелки и `Enter` достались бы полю.
  late final FocusNode _field = FocusNode(debugLabel: 'key-bindings', onKeyEvent: _onKey);

  final FcPickPage _page = FcPickPage();

  int _selected = 0;

  /// Привязка, для которой ждём нажатия; null — захвата нет.
  String? _capturing;

  /// Столкновение, о котором спрашиваем: что назначаем и у кого отнимаем.
  _Conflict? _conflict;

  /// Что сказать человеку: почему нажатие не подошло.
  String _complaint = '';

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() => _selected = 0));
  }

  @override
  void dispose() {
    _query.dispose();
    _field.dispose();
    super.dispose();
  }

  List<KeyBindingItem> get _found {
    final rows = FcPickList.filter([for (final item in widget.items) item.row('')], _query.text);
    final byId = {for (final item in widget.items) item.id: item};
    return [
      for (final row in rows)
        if (byId[row.id] case final item?) item,
    ];
  }

  KeyBindingItem? get _current {
    final found = _found;
    return found.isEmpty ? null : found[_selected.clamp(0, found.length - 1)];
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_conflict != null) {
      return _answerConflict(event);
    }
    if (_capturing != null) {
      return _capture(event);
    }
    return _browse(event);
  }

  /// Обычная ходьба по списку.
  KeyEventResult _browse(KeyEvent event) {
    final found = _found;
    final moved = FcPickList.moveSelection(event, selected: _selected, count: found.length, page: _page);
    if (moved != null) {
      setState(() {
        _selected = moved < 0 ? found.length - 1 : moved;
        _complaint = '';
      });
      return KeyEventResult.handled;
    }

    final item = _current;
    if (item == null) {
      return KeyEventResult.ignored;
    }

    final keys = KeyCombination.fromEvent(event);
    if (keys == _enter) {
      setState(() {
        _complaint = item.cannotEdit;
        _capturing = item.editable ? item.id : null;
      });
      return KeyEventResult.handled;
    }
    if (keys == _clear) {
      widget.onClear(item.id);
      return KeyEventResult.handled;
    }
    if (keys == _default) {
      widget.onReset(item.id);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Захват: следующее сочетание и становится клавишей.
  KeyEventResult _capture(KeyEvent event) {
    final keys = KeyCombination.fromEvent(event);
    // Одни модификаторы сочетанием не бывают: пока нажат только `Cmd`, ждём
    // дальше.
    if (keys == null) {
      return KeyEventResult.handled;
    }
    if (keys == _escape) {
      setState(() => _capturing = null);
      return KeyEventResult.handled;
    }

    final id = _capturing!;
    final holder = widget.occupiedBy(id, keys.toString());
    setState(() {
      _capturing = null;
      _conflict = holder == null ? null : _Conflict(id: id, keys: keys.toString(), holder: holder);
    });
    if (holder == null) {
      widget.onAssign(id, keys.toString());
    }
    return KeyEventResult.handled;
  }

  /// Ответ на вопрос о столкновении: отнять или оставить.
  KeyEventResult _answerConflict(KeyEvent event) {
    final keys = KeyCombination.fromEvent(event);
    final conflict = _conflict!;
    if (keys == _enter) {
      setState(() => _conflict = null);
      widget.onAssign(conflict.id, conflict.keys);
      return KeyEventResult.handled;
    }
    if (keys == _escape) {
      setState(() => _conflict = null);
      return KeyEventResult.handled;
    }
    // Пока вопрос не решён, окно занято им: чужие нажатия сюда не проходят.
    return KeyEventResult.handled;
  }

  /// Строка над списком: что делаем сейчас.
  ///
  /// Место под неё отведено всегда, даже когда сказать нечего: строка, то
  /// появляющаяся, то пропадающая, дёргала бы список под руками.
  String get _hint {
    if (_conflict case final conflict?) {
      return context.strings.tr(
        '{keys} belongs to «{command}». Enter — take it, Esc — leave it',
        args: {'keys': conflict.keys, 'command': conflict.holder},
      );
    }
    if (_capturing != null) {
      return context.strings.tr('Press the combination; Esc — cancel');
    }
    if (_complaint.isNotEmpty) {
      return _complaint;
    }
    return context.strings.tr('Enter — set, Bsp — clear, Cmd-R — default');
  }

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;
    final limits = dialogContentLimits(context, titled: true);
    final capturingId = _capturing;

    return ConstrainedBox(
      constraints: limits,
      child: SizedBox(
        width: MediaQuery.sizeOf(context).width * metrics.paletteWidthFactor,
        child: FcDialogBody(
          insets: FcDialogInsets.vertical,
          actions: [
            FcButton(
              label: context.strings.tr('Reset all'),
              onPressed: widget.items.every((item) => item.isDefault) ? null : widget.onResetAll,
            ),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: metrics.dialogHorizontalPadding),
                child: FcTextField(
                  controller: _query,
                  focusNode: _field,
                  autofocus: true,
                  hintText: context.strings.tr('Command'),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  metrics.dialogHorizontalPadding,
                  metrics.dialogPadding,
                  metrics.dialogHorizontalPadding,
                  metrics.dialogPadding,
                ),
                // Своим `Text`, а не `FcText`: строка эта служебная — что
                // делаем сейчас, — и набрана она приглушённо, а вопрос о
                // столкновении цветом отказа.
                child: Text(
                  _hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.statusStyle.copyWith(
                    color: _conflict != null || _complaint.isNotEmpty ? theme.colors.error : theme.colors.secondaryText,
                  ),
                ),
              ),
              Flexible(
                child: FcPickList(
                  rows: [for (final item in _found) item.row(item.id == capturingId ? '…' : '')],
                  query: _query.text,
                  selected: _selected,
                  page: _page,
                  emptyMessage: context.strings.tr('No such command'),
                  onTap:
                      (id) => setState(() {
                        _selected = _found.indexWhere((item) => item.id == id);
                        _complaint = '';
                      }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// О чём спрашиваем: какую клавишу назначаем и у кого она сейчас.
class _Conflict {
  const _Conflict({required this.id, required this.keys, required this.holder});

  final String id;
  final String keys;
  final String holder;
}
