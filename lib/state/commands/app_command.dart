import '../../model/app/application.dart';
import '../../model/app/panel.dart';
import '../../model/tree/fs_node.dart';
import 'key_combination.dart';

/// Привязка комбинации клавиш к команде.
///
/// Привязка не принадлежит команде: её ставит, хранит и разбирает реестр
/// (`CommandRegistry`). Так их можно будет менять из настроек, не трогая код
/// команд, а сами команды остаются самостоятельными действиями.
class KeyBinding {
  KeyBinding(String keys, this.commandId, {this.nameMatch}) : keys = KeyCombination.parse(keys);

  const KeyBinding.combination(this.keys, this.commandId, {this.nameMatch});

  final KeyCombination keys;

  /// Идентификатор команды ([AppCommand.id]), а не сама команда: привязки
  /// хранятся в настройках, где живут только идентификаторы.
  final String commandId;

  /// Необязательный фильтр по имени объекта под курсором. Позволяет повесить на
  /// Enter разные команды для `*.app`, `*.zip` и обычных файлов — приём
  /// референса (`BindingProperties.nodeValue`). Это условие выбора команды,
  /// а не данные для неё.
  final RegExp? nameMatch;

  bool matches(KeyCombination combination, FsNode? node) {
    if (combination != keys) {
      return false;
    }
    final pattern = nameMatch;
    return pattern == null || (node != null && pattern.hasMatch(node.name));
  }

  @override
  String toString() => '$keys → $commandId';
}

/// Условия, в которых выполняется команда: активная панель и объекты, с
/// которыми работать.
///
/// Всё здесь — интерфейсы ([Application], [Panel]): команда работает с API
/// приложения, а не с конкретными контроллерами, и потому не зависит от того,
/// как они устроены.
///
/// Больше в контексте ничего нет намеренно — команда не должна знать, чем её
/// вызвали: клавишей, кнопкой внизу окна или списком команд.
class CommandContext {
  const CommandContext({required this.app, required this.panel, this.node, this.targets = const []});

  final Application app;

  /// Активная панель — источник операции.
  final Panel panel;

  /// Объект под курсором.
  final FsNode? node;

  /// Помеченные объекты, а если пометки нет — объект под курсором.
  /// Именно с этим списком работают файловые операции.
  final List<FsNode> targets;

  /// Пассивная панель — приёмник операций.
  Panel get target => app.passivePanel;
}

/// Действие приложения.
///
/// Команда описывает только себя: название, условие выполнимости и поведение.
///
/// **Команда не знает, чем её вызвали и где её показывают.** Всё, на что она
/// опирается, — это [CommandContext]: активная панель и выбранные объекты.
/// Ни привязок клавиш, ни места в интерфейсе она не объявляет: привязками
/// заведует реестр, а нижняя панель — это та же клавиатура, только
/// нарисованная, и она сама спрашивает, что закреплено за `F5`.
///
/// Поэтому привязки клавиш можно будет менять из настроек, а любую команду —
/// выполнить из списка команд, как в VS Code. Если два действия отличаются
/// поведением («войти» и «открыть системой»), это две разные команды, а не
/// одна с параметром.
abstract class AppCommand {
  /// Стабильный идентификатор для настроек, логов и поиска команды в коде:
  /// `panel.open`, `file.copy`. Пользователю не показывается.
  String get id;

  /// Название команды для пользователя: подпись кнопки внизу окна и строка
  /// в списке команд. В интерфейсе видно именно его — ни [id], ни имя класса
  /// наружу не показываются, поэтому название должно читаться вне контекста.
  String get label;

  /// Вызывается один раз при установке. false — команда не устанавливается
  /// (например, недоступна на этой платформе).
  bool init(Application app) => true;

  /// Можно ли выполнить прямо сейчас.
  bool isExecutable(CommandContext context);

  Future<void> execute(CommandContext context);

  /// Вызывается при завершении приложения.
  Future<void> shutdown() async {}
}

/// Команда, которая ещё не реализована: клавиша за ней уже закреплена, кнопка
/// внизу окна показана и приглушена. Так связка «кнопка ↔ команда ↔ клавиша»
/// проверяется сейчас, а не переписывается вместе с файловыми операциями.
class PlaceholderCommand extends AppCommand {
  PlaceholderCommand({required this.id, required this.label});

  @override
  final String id;

  @override
  final String label;

  @override
  bool isExecutable(CommandContext context) => false;

  @override
  Future<void> execute(CommandContext context) async {}
}
