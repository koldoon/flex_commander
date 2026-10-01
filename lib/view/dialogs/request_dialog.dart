import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/widgets.dart';

/// Окно для запроса, который задаёт не команда, а приложение: пароль, права
/// администратора, необработанная ошибка.
///
/// Раньше каждый такой запрос рисовался своим слоем над всеми окнами — со
/// своими правилами фокуса и места, сбоку от общей стопки. Теперь окно
/// кладётся **в стопку** (`docs/spec/child-dialogs.md`, §4.5): те же правила
/// места, фокуса и закрытия, что у всех.
///
/// Сам виджет ничего не рисует. Он следит за запросом: появился — окно в
/// стопку, сменился — прежнее закрыто, новое поднято, ушёл — окно закрыто.
/// Закрыли окно-родителя — окну говорится отказ, и запрос получает «нет».
class RequestDialog<T extends Object> extends StatefulWidget {
  const RequestDialog({
    super.key,
    required this.view,
    required this.listenable,
    required this.current,
    required this.identity,
    required this.spec,
    this.childOfTop = true,
  });

  final ApplicationView view;

  /// Что слушать: запрос меняется в нём.
  final Listenable listenable;

  /// Запрос сейчас; null — спрашивать не о чем.
  final T? Function() current;

  /// Чем один запрос отличается от другого: сменилось — окно переоткрывается.
  final Object Function(T request) identity;

  /// Окно для запроса; `parent` — родитель, если он есть.
  final DialogSpec Function(BuildContext context, T request, String? parent) spec;

  /// Берёт ли окно родителем верхнее окно стопки.
  ///
  /// Пароль и права спрашивают из-за работы, и работа эта — обычно то окно,
  /// что сверху. Необработанная ошибка родителя не берёт: закрытие любого
  /// другого окна не должно унести её непрочитанной.
  final bool childOfTop;

  @override
  State<RequestDialog<T>> createState() => _RequestDialogState<T>();
}

class _RequestDialogState<T extends Object> extends State<RequestDialog<T>> {
  String? _dialogId;
  Object? _shownFor;

  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_schedule);
    _schedule();
  }

  @override
  void didUpdateWidget(RequestDialog<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.listenable, widget.listenable)) {
      oldWidget.listenable.removeListener(_schedule);
      widget.listenable.addListener(_schedule);
      _schedule();
    }
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_schedule);
    if (_dialogId case final open?) {
      widget.view.closeDialog(open);
    }
    super.dispose();
  }

  /// Окно поднимается после кадра: показывать его посреди уведомления нельзя.
  void _schedule() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _sync() {
    if (!mounted) {
      return;
    }
    final request = widget.current();
    final wanted = request == null ? null : widget.identity(request);
    if (wanted == _shownFor && (wanted == null || _isOpen)) {
      return;
    }
    final view = widget.view;
    if (_dialogId case final open?) {
      _dialogId = null;
      view.closeDialog(open);
    }
    _shownFor = wanted;
    if (request != null) {
      _dialogId = view.showDialog(widget.spec(context, request, widget.childOfTop ? view.topDialogId : null));
    }
  }

  bool get _isOpen => widget.view.openDialogs.any((dialog) => dialog.id == _dialogId);

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
