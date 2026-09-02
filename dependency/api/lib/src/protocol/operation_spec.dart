import 'entry_ref.dart';

/// Заявка на работу: что делать, над чем и с чем.
///
/// Работа рождается там, где живут источники, — команда только называет её и
/// приносит доводы (`docs/spec/client-server.md`, §5.4). Поэтому здесь нет ни
/// узлов, ни движка: [kind] говорит, кого звать, [targets] — над чем, а
/// остальное лежит в [options] обычными значениями.
///
/// [options] — карта, а не поля: свои работы объявляют модули, и их доводы
/// ядру неведомы. Тем же приёмом устроен запуск команды с параметрами
/// (`CommandInvocation`), и второго способа передать «сжатие: нормальное»
/// заводить незачем.
class OperationSpec {
  const OperationSpec({
    required this.kind,
    this.targets = const Targets.paths([]),
    this.destination,
    this.destinationPath,
    this.options = const {},
  });

  /// Кого звать: `file.copy`, `zip.pack`. Объявляет имя тот же модуль, что и
  /// саму работу.
  final String kind;

  /// Над чем работать — именем набора, а не перечислением.
  final Targets targets;

  /// Панель-приёмник; её каталог и есть место назначения.
  final PanelId? destination;

  /// Или прямой путь — когда приёмник назвали строкой: перетаскивание,
  /// сценарий, повтор из истории.
  final String? destinationPath;

  /// Доводы работы: имя архива, степень сжатия, идти ли по ссылкам.
  final Map<String, Object?> options;

  T? option<T>(String name) {
    final value = options[name];
    return value is T ? value : null;
  }

  @override
  String toString() => 'OperationSpec($kind)';
}

/// Работы, которые есть у файлового менеджера всегда.
///
/// Имена — часть языка границы, а не подробность ядра: заявку собирает команда
/// на одной стороне, а исполняет работу другая, и общее у них ровно это имя.
/// Работы модулей объявляют свои имена сами и здесь не перечисляются.
abstract final class FileOperations {
  static const String copy = 'file.copy';
  static const String move = 'file.move';
  static const String remove = 'file.remove';
  static const String makeDirectory = 'file.makeDirectory';
  static const String rename = 'file.rename';

  /// Идти ли по символическим ссылкам. По умолчанию нет: ссылка переносится
  /// ссылкой, как в mc.
  static const String followLinks = 'followLinks';

  /// В корзину или совсем.
  static const String toTrash = 'toTrash';

  /// Новое имя — для создания каталога и переименования.
  static const String name = 'name';
}

/// Что говорят **в уже идущую** работу.
///
/// Одним входом на все реплики: сказать в идущую работу её же потоком событий
/// нельзя — поток идёт в другую сторону, — а заводить по методу на каждую
/// реплику значит собирать свалку. Это тот же урок, что и в прошлый раз
/// (`spec/isolated-core.md`, §6.1).
sealed class OperationInput {
  const OperationInput();
}

/// Прекратить: молча и сразу.
final class CancelInput extends OperationInput {
  const CancelInput();
}

/// Попросить прервать: работа сама решит, спросить ли человека.
///
/// Отдельно от [CancelInput], потому что вопрос «прервать работу?» задаёт сама
/// работа между своими шагами, и здешняя сторона его не исполняет, а
/// пересылает.
final class SoftCancelInput extends OperationInput {
  const SoftCancelInput();
}

/// Ответ на вопрос, заданный по ходу дела.
final class AnswerInput extends OperationInput {
  const AnswerInput(this.optionId, {this.text = ''});

  /// Какой вариант выбрали: `overwrite`, `skip`, `abort`.
  final String optionId;

  /// Что набрали, если у вопроса было поле ввода.
  final String text;
}

/// Вопрос работы значением: то, что уезжает на экран.
///
/// Сам `OperationRequest` через границу не поедет — внутри у него `Completer`,
/// а общей памяти у сторон нет. Наружу едет описание вопроса, обратно —
/// [AnswerInput] с именем выбранного варианта.
class AskSpec {
  const AskSpec({
    required this.message,
    required this.options,
    required this.enterOptionId,
    this.escapeOptionId,
    this.inputLabel,
    this.secret = false,
  });

  final String message;

  /// Варианты ответа: имя для кода и подпись для кнопки.
  final Map<String, String> options;

  /// Какую кнопку подсветить и нажать по `Enter`.
  final String enterOptionId;

  /// Что означает `Esc`; null — ничего, вопрос закрывают кнопкой.
  final String? escapeOptionId;

  /// Подпись поля ввода; null — вопрос только из кнопок.
  final String? inputLabel;

  /// Набранное не показывать: пароль.
  final bool secret;
}

/// Чем кончилась работа.
///
/// Четыре исхода, а не два: прерванное копирование не показывает окна с
/// ошибкой, и отличать отмену от беды приходится везде
/// (`docs/spec/client-server.md`, §5.3).
enum OperationOutcome { done, canceled, failed }
