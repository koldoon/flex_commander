import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';

/// Имена работ этого модуля.
abstract final class RenameOperations {
  /// Переименовать пачку: заявка несёт **готовые пары** «путь → новое имя».
  static const String batch = 'file.renameBatch';

  static const String pathsOption = 'paths';
  static const String namesOption = 'names';
}

/// Готовые пары «что → как».
///
/// **Маска, счётчик и регистр в ядро не едут.** Имена считает экран, показывает
/// их человеку в таблице и их же отправляет: иначе у приложения появился бы
/// второй ответ на вопрос «во что превратится это имя», и он однажды разошёлся
/// бы с тем, что человек утвердил глазами (`docs/spec/multi-rename.md`, §2).
///
/// Два списка строк, а не карта: простейшее, что переживает границу изолята, —
/// тем же приёмом едет правка атрибутов.
class RenameBatch {
  const RenameBatch(this.paths, this.names);

  factory RenameBatch.fromOptions(Map<String, Object?> options) => RenameBatch(
    [...?(options[RenameOperations.pathsOption] as List?)?.cast<String>()],
    [...?(options[RenameOperations.namesOption] as List?)?.cast<String>()],
  );

  factory RenameBatch.of(Map<String, String> renames) => RenameBatch([...renames.keys], [...renames.values]);

  final List<String> paths;
  final List<String> names;

  bool get isEmpty => paths.isEmpty || paths.length != names.length;

  int get length => paths.length;

  Map<String, Object?> toOptions() => {RenameOperations.pathsOption: paths, RenameOperations.namesOption: names};
}

/// Переименование пачки — работа ядра.
///
/// Порядок считает она, и считает **по ходу**: только здесь известно, кто уже
/// уехал и чьё имя освободилось. Сперва идут те, чья цель свободна — это
/// закрывает весь сдвиг ряда (`001 → 002 → 003`) без единого временного имени;
/// а если свободных не осталось, впереди цикл, и один его участник уезжает
/// через временное имя (`docs/spec/multi-rename.md`, §9).
class RenameBatchWork {
  const RenameBatchWork({this.strings});

  final Strings? strings;

  Operation<OperationInputs, void> operation() {
    final said = strings ?? StringsRegistry();

    return TaskOperation<OperationInputs, void>((op, inputs) async {
      final batch = RenameBatch.fromOptions(inputs.options);
      if (batch.isEmpty) {
        return;
      }
      // Цели пришли узлами, имена — строками: сопоставляются путём. По месту в
      // списке целей сопоставлять нельзя — пометка отдаёт их в своём порядке, а
      // нумеровал человек в порядке списка.
      final nodes = {for (final node in inputs.targets) node.pathString: node};

      final pending = <_Step>[];
      for (var at = 0; at < batch.length; at++) {
        final node = nodes[batch.paths[at]];
        if (node != null) {
          pending.add(_Step(node, batch.names[at]));
        }
      }
      if (pending.isEmpty) {
        return;
      }

      // Одна цель — отказ пробрасывается без вопроса, и окно возвращается к
      // форме: то же правило, что у правки атрибутов и у `Shift-F6`
      // (`docs/spec/dialog-run-phase.md`).
      final alone = pending.length == 1;
      final total = pending.length;
      var skipAll = false;
      var done = 0;

      /// Занято ли имя кем-то из тех, кто ещё не уехал.
      bool occupied(_Step step, String name) =>
          pending.any((other) => other != step && _same(other.node.name, name) && _sameHome(other, step));

      Future<void> move(_Step step, String name, {required bool last}) async {
        step.node = await op.delegate(inputs.editor.rename(), RenameParams(step.node, name));
        if (last) {
          op.report(message: said.tr('Renaming…'), itemName: name, itemsTransferred: ++done, itemsTotal: total);
        }
      }

      var temps = 0;
      while (pending.isNotEmpty) {
        op.checkCanceled();

        final free = [
          for (final step in pending)
            if (!occupied(step, step.name)) step,
        ];
        if (free.isEmpty) {
          // Свободных целей нет — впереди цикл. Один участник уезжает во
          // временное имя и освобождает своё; прервали работу здесь — на диске
          // остаётся файл с **видимым** временным именем, и это честнее тихой
          // потери.
          final step = pending.first;
          try {
            await move(step, '${step.node.name}.fc-rename-${++temps}', last: false);
          } on OperationCanceled {
            rethrow;
          } on FsError catch (error) {
            pending.remove(step);
            if (alone) {
              rethrow;
            }
            if (!skipAll) {
              final answer = await _asked(op, said, error);
              if (answer == _cancel) {
                throw const OperationCanceled();
              }
              skipAll = answer == _skipAll;
            }
          }
          continue;
        }

        for (final step in free) {
          op.checkCanceled();
          try {
            await move(step, step.name, last: true);
          } on OperationCanceled {
            rethrow;
          } on FsError catch (error) {
            if (alone) {
              rethrow;
            }
            if (!skipAll) {
              final answer = await _asked(op, said, error);
              if (answer == _cancel) {
                throw const OperationCanceled();
              }
              skipAll = answer == _skipAll;
            }
          }
          pending.remove(step);
        }
      }
    });
  }

  /// Спрашивает, что делать с отказавшим, и отдаёт имя ответа.
  static Future<String> _asked(TaskOperation<Object?, Object?> op, Strings said, FsError error) async {
    final answer = await op.ask(
      OperationRequest(
        message: said.describe(error),
        options: [
          OperationRequestOption(_skip, said.tr('Skip')),
          OperationRequestOption(_skipAll, said.tr('Skip all')),
          OperationRequestOption(_cancel, said.tr('Cancel')),
        ],
        enterOption: OperationRequestOption(_skip, said.tr('Skip')),
        escapeOption: OperationRequestOption(_cancel, said.tr('Cancel')),
      ),
    );
    return answer.id;
  }

  static const String _skip = 'skip';
  static const String _skipAll = 'skipAll';
  static const String _cancel = 'cancel';

  /// Имена сличаются без учёта регистра — на macOS его не различает и файловая
  /// система.
  static bool _same(String left, String right) => left.toLowerCase() == right.toLowerCase();

  /// Спорят только соседи по каталогу: цели бывают из разных мест.
  static bool _sameHome(_Step left, _Step right) =>
      left.node.parentDirectory?.pathString == right.node.parentDirectory?.pathString;
}

class _Step {
  _Step(this.node, this.name);

  /// Узел — **меняется по ходу**: переименование отдаёт новый.
  FsNode node;

  /// Куда этот шаг должен приехать в итоге.
  final String name;
}
