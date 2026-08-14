import '../../model/tree/fs_node.dart';
import '../app_controller.dart';
import '../panel_controller.dart';
import 'key_combination.dart';

/// Слот нижней панели. Номер слота — это номер функциональной клавиши.
enum FunctionKeySlot {
  f1,
  f2,
  f3,
  f4,
  f5,
  f6,
  f7,
  f8,
  f9,
  f10;

  int get number => index + 1;

  KeyCombination get keys => KeyCombination('F$number');
}

/// Привязка команды к комбинации клавиш.
class KeyBinding {
  KeyBinding(String keys, {this.nameMatch, this.parameters = const {}}) : keys = KeyCombination.parse(keys);

  const KeyBinding.combination(this.keys, {this.nameMatch, this.parameters = const {}});

  final KeyCombination keys;

  /// Необязательный фильтр по имени объекта под курсором. Позволяет повесить на
  /// Enter разные команды для `*.app`, `*.zip` и обычных файлов — приём
  /// референса (`BindingProperties.nodeValue`).
  final RegExp? nameMatch;

  /// Параметры, с которыми команда вызывается именно по этой привязке:
  /// например `Cmd-O` открывает объект системой, не входя в каталог.
  final Map<String, Object?> parameters;

  bool matches(KeyCombination combination, FsNode? node) {
    if (combination != keys) {
      return false;
    }
    final pattern = nameMatch;
    return pattern == null || (node != null && pattern.hasMatch(node.name));
  }
}

/// Условия, в которых выполняется команда.
class CommandContext {
  const CommandContext({
    required this.app,
    required this.panel,
    this.node,
    this.targets = const [],
    this.parameters = const {},
  });

  final AppController app;

  /// Активная панель — источник операции.
  final PanelController panel;

  /// Объект под курсором.
  final FsNode? node;

  /// Помеченные объекты, а если пометки нет — объект под курсором.
  /// Именно с этим списком работают файловые операции.
  final List<FsNode> targets;

  final Map<String, Object?> parameters;

  /// Пассивная панель — приёмник операций.
  PanelController get target => app.passivePanel;

  T? parameter<T>(String name) {
    final value = parameters[name];
    return value is T ? value : null;
  }
}

/// Действие приложения.
///
/// Команда описывает себя целиком: свои привязки клавиш, место в нижней панели
/// и условие выполнимости. Кнопка внизу окна и горячая клавиша — два вида на
/// одну и ту же команду, поэтому они не могут разъехаться.
abstract class AppCommand {
  /// Стабильный идентификатор для настроек и логов: `panel.open`, `file.copy`.
  String get id;

  /// Подпись для нижней панели.
  String get label;

  /// Слот нижней панели; null — команда кнопкой не показывается.
  FunctionKeySlot? get functionKey => null;

  List<KeyBinding> get bindings;

  /// Вызывается один раз при установке. false — команда не устанавливается
  /// (например, недоступна на этой платформе).
  bool init(AppController app) => true;

  /// Можно ли выполнить прямо сейчас.
  bool isExecutable(CommandContext context);

  Future<void> execute(CommandContext context);

  /// Вызывается при завершении приложения.
  Future<void> shutdown() async {}
}

/// Команда, которая ещё не реализована: место в нижней панели занято, кнопка
/// показана и приглушена. Так связка «кнопка ↔ команда ↔ клавиша» проверяется
/// сейчас, а не переписывается вместе с файловыми операциями.
class PlaceholderCommand extends AppCommand {
  PlaceholderCommand({required this.id, required this.label, required this.functionKey, List<KeyBinding>? bindings})
    : bindings = bindings ?? [KeyBinding.combination(functionKey.keys)];

  @override
  final String id;

  @override
  final String label;

  @override
  final FunctionKeySlot functionKey;

  @override
  final List<KeyBinding> bindings;

  @override
  bool isExecutable(CommandContext context) => false;

  @override
  Future<void> execute(CommandContext context) async {}
}
