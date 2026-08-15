/// Взаимодействие с пользователем: вопросы, подтверждения и сообщения.
///
/// Команды спрашивают через этот интерфейс и ничего не знают о виджетах —
/// в референсе эту роль играл `IApplication.popupManager`. Реализация живёт
/// в слое представления, а в тестах подставляется своя.
abstract interface class UserInteraction {
  /// Запрос строки у пользователя. null — отказался.
  Future<String?> promptText({
    required String title,
    String initialText = '',
    String? hint,
    String confirmLabel = 'OK',
  });

  /// Подтверждение действия. false — отказался.
  Future<bool> confirm({required String title, String? message, String confirmLabel = 'OK'});

  /// Сообщение об ошибке.
  Future<void> showError({required String title, String? message});
}

/// Молчаливая реализация: ничего не спрашивает и ничего не показывает.
///
/// Нужна там, где интерфейса нет вовсе: в тестах контроллеров и при запуске
/// без окна. Команда, получившая отказ, просто не выполняется.
class SilentUserInteraction implements UserInteraction {
  const SilentUserInteraction();

  @override
  Future<String?> promptText({
    required String title,
    String initialText = '',
    String? hint,
    String confirmLabel = 'OK',
  }) async => null;

  @override
  Future<bool> confirm({required String title, String? message, String confirmLabel = 'OK'}) async => false;

  @override
  Future<void> showError({required String title, String? message}) async {}
}
