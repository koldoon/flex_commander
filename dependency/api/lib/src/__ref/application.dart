import 'package:fc_api/fc_api.dart';

// Всё остальное из наброска рабочей области уже в настоящем API: области и
// стопки (ViewportPosition, ViewportState, ViewPort), окна (DialogSpec,
// showDialog, dialogs), фокус (activeArea, sourceArea, setFocus), а тосты,
// доля разделителя и геометрия окна — на самом Application.

/// Чего в настоящем API ещё нет.
abstract interface class ApplicationView {
  /// Поднимает окно работы, которая встала и ждёт человека.
  ///
  /// Вид находится по типу того, что операция выставила
  /// ([InteractiveOperationStatus.request]), а не по тому, чья это работа, —
  /// поэтому поднять может кто угодно: кнопка в статусной области, панель,
  /// дожидающаяся чтения каталога, тест.
  ///
  /// Сегодня окно возвращает тот, кто работу завёл
  /// (`OperationRun.bringToFront`), и этого хватает: вопрос показывает то же
  /// окно. Не хватит, когда спрашивать начнёт модуль, к команде отношения не
  /// имеющий, — вход в зашифрованный архив, которого ждёт панель.
  void showAttention(Operation operation);
}
