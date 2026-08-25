import 'package:flutter/foundation.dart';

// FcModule, FcRegistry, FcServices и FcContext уже в настоящем API — вместе с
// view<S>() по типу состояния и resolveOrNull. Фабрика команды там же
// (AppCommandFactory), и создаётся команда один раз: она прототип.
//
// Не хватает только strings(locale, table): это Б1, и она ещё не наступила.

/// Строки интерфейса.
///
/// Свой реестр, без `intl` и кодогенерации: строки приносят модули, и знать
/// заранее их состав нельзя. Неизвестный язык или идентификатор откатывается
/// к английскому, а потом к самому идентификатору — пустое место в интерфейсе
/// хуже, чем невпопад переведённое слово.
///
/// [Listenable], потому что язык переключают на ходу: `AppCommand.label` —
/// геттер и вычисляется отсюда, поэтому нижний ряд кнопок и список команд
/// подписываются на строки и перерисовываются сами.
abstract interface class Strings implements Listenable {
  String get locale;

  String tr(String id, {Map<String, Object?> args = const {}});

  String plural(String id, int count);
}
