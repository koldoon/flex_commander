import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Акцентный цвет, выбранный в системе.
///
/// Тот, которым macOS красит выделение, кнопку по умолчанию и обводку фокуса.
/// Вещь платформенная (сквозное правило 2): из Flutter его не узнать. Службы нет
/// — значит, спросить некого, и оформления остаются с постоянным синим; так и
/// было до неё (`docs/spec/macos-themes.md`, §5).
///
/// [Listenable], а не поток: акцент меняют в системных настройках, оформление
/// на это перекладывается, и для приложения это обычное изменение состояния —
/// такое же, как смена самой темы.
abstract interface class SystemAccent implements Listenable {
  /// Цвета для светлой внешности; `null` — не спрашивали или спросить некого.
  ///
  /// Обе внешности сразу, потому что оформление выбирают руками: светлое
  /// обязано взять свои цвета даже тогда, когда система стоит тёмной.
  SystemAccentColors? get light;

  /// Цвета для тёмной внешности.
  SystemAccentColors? get dark;

  /// Спросить систему и запомнить ответ.
  Future<void> refresh();
}

/// Что система красит акцентом в одной внешности (`docs/spec/macos-themes.md`,
/// §6а).
///
/// Три цвета, а не один акцент: выделенное и выделение текста система
/// пересчитывает сама — под акцент и под настройку «Цвет выделения», — и
/// вывести их из акцента нельзя.
@immutable
class SystemAccentColors {
  const SystemAccentColors({required this.accent, required this.selection, required this.textSelection});

  /// `controlAccentColor` — кнопка по умолчанию, обводка фокуса, ход работы.
  final Color accent;

  /// `selectedContentBackgroundColor` — выделенное в фокусе: строка списка,
  /// активная плашка.
  final Color selection;

  /// `selectedTextBackgroundColor` — выделение текста.
  final Color textSelection;

  @override
  bool operator ==(Object other) =>
      other is SystemAccentColors &&
      other.accent == accent &&
      other.selection == selection &&
      other.textSelection == textSelection;

  @override
  int get hashCode => Object.hash(accent, selection, textSelection);
}
