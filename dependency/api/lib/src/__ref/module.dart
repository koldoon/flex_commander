import 'package:fc_api/fc_api.dart' show FcContext;
import 'package:flutter/foundation.dart';

import 'application.dart';
import 'command.dart';

/// Как создать команду. Зависимости подставляет контейнер.
///
/// Экземпляр создаётся один раз, при установке: команда — прототип и состояния
/// прогона не держит.
typedef FcCommandFactory = AppCommand Function(FcContext context);

// FcModule уже в настоящем API.

// FcRegistry уже в настоящем API — вместе с view<S>() по типу состояния.
// Не хватает только strings(locale, table): это Б1, и она ещё не наступила.

// FcServices и FcContext уже в настоящем API, включая resolveOrNull.

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
