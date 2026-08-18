import 'app_command.dart';

/// Разделитель панелей — посередине.
///
/// Отдельная команда, а не строчка в обработчике мыши: разделитель можно
/// вернуть в середину и двойным кликом, и средней кнопкой, а когда-нибудь — из
/// списка команд или с клавиатуры. Все эти способы должны делать ровно одно и
/// то же, а сделать одно и то же по-разному проще всего тогда, когда действие
/// живёт в нескольких местах.
class CenterSplitCommand extends AppCommand {
  /// Идентификатор рядом с классом: команду запускает не только клавиатура,
  /// но и разделитель, а строка, которую надо держать совпадающей с `id`
  /// вручную, однажды разойдётся с ним.
  static const String commandId = 'app.split.center';

  /// Ровно пополам.
  static const double centerRatio = 0.5;

  @override
  String get id => commandId;

  @override
  String get label => 'Center split';

  @override
  String get description => 'Give both panels the same width';

  /// Уже посередине — делать нечего; в списке команд такая строка приглушена.
  @override
  bool isExecutable(CommandContext context) => context.app.splitRatio != centerRatio;

  @override
  Future<void> execute() async => context.app.setSplitRatio(centerRatio);
}
