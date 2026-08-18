import 'package:fc_api/fc_api.dart';

import '../state/commands/default_commands.dart';

/// Все команды приложения одним модулем — временно.
///
/// Команды разъедутся по своим модулям (навигация, файловые операции, справка)
/// в следующих шагах; пока они держатся вместе, чтобы сборка приложения уже
/// шла через модули, а привязки клавиш не переехали дважды.
class LegacyCommands implements FcModule {
  const LegacyCommands();

  @override
  String get id => 'fc.legacy_commands';

  @override
  String get title => 'Built-in commands';

  @override
  void install(FcRegistrar registrar) {
    for (final factory in defaultCommands(
      opener: (path) => registrar.services.resolve<SystemOpener>()(path),
      // Справка показывает содержимое реестра, а реестра во время объявления
      // ещё нет: команда получает не его, а способ его спросить.
      registry: () => registrar.services.resolve<CommandRegistry>(),
    )) {
      registrar.command((context) => factory());
    }

    for (final binding in defaultKeyBindings()) {
      registrar.binding(binding);
    }
  }
}
