import 'dart:async';

import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:re_editor/re_editor.dart';

/// Поиск по показанному тексту.
///
/// Обёртка над поиском `re_editor`: сам он умеет и считать совпадения, и
/// подсвечивать их все разом, и ходить по ним вперёд-назад — но рассчитан на
/// собственную панель, которой у нас нет. У нас строку спрашивает окно команды,
/// а дальше человек ходит по совпадениям клавишами.
///
/// Живёт у экрана, а не у вида: искать просит команда, а она о виджетах ничего
/// не знает.
class FcTextFinder {
  FcTextFinder(this.controller) : findController = CodeFindController(controller);

  /// Текст, по которому ищем, и курсор в нём.
  final CodeLineEditingController controller;

  /// Поиск библиотеки — им пользуется поле показа, чтобы подсвечивать
  /// найденное. Наружу из приложения не ходит: искать просят через `search`,
  /// `next` и `previous`.
  ///
  /// `Code…` в имени типа — словарь `re_editor`, не наш: у него всё поле
  /// называется редактором кода. Наши имена в этом пакете про текст.
  final CodeFindController findController;

  /// Последняя строка поиска: окно предлагает её снова, чтобы повторить поиск
  /// было нажатием, а не набором.
  String get pattern => findController.value?.option.pattern ?? '';

  bool get caseSensitive => findController.value?.option.caseSensitive ?? false;

  bool get regex => findController.value?.option.regex ?? false;

  /// Сколько совпадений нашлось.
  int get matchCount => findController.value?.result?.matches.length ?? 0;

  /// Который из них показан сейчас, считая с единицы. Ноль — не показан ни один.
  int get currentIndex {
    final CodeFindResult? result = findController.value?.result;
    return result == null || result.matches.isEmpty ? 0 : result.index + 1;
  }

  /// Ищет и показывает первое совпадение. Возвращает, сколько их всего.
  ///
  /// Поиск у библиотеки идёт в изоляте, поэтому ждём, пока он закончится: по
  /// его итогу команда либо показывает счёт, либо говорит, что не нашлось.
  Future<int> search(String text, {bool caseSensitive = false, bool regex = false}) async {
    if (text.isEmpty) {
      clear();
      return 0;
    }

    // Поиск включается один раз: пока значение пустое, правка строки его не
    // разбудит. Второй раз звать нельзя — `findMode` подставляет в строку
    // поиска **выделенное** в тексте, а выделено у нас прошлое совпадение.
    if (findController.value == null) {
      findController.findMode();
    }

    final CodeFindOption? option = findController.value?.option;
    if (option != null) {
      if (option.caseSensitive != caseSensitive) {
        findController.toggleCaseSensitive();
      }
      if (option.regex != regex) {
        findController.toggleRegex();
      }
    }

    findController.findInputController.text = text;
    await _settled(text);
    _reveal();
    return matchCount;
  }

  /// Следующее совпадение по кругу. `false` — искать нечего.
  bool next() {
    if (matchCount == 0) {
      return false;
    }
    findController.nextMatch();
    _reveal();
    return true;
  }

  /// Предыдущее совпадение по кругу.
  bool previous() {
    if (matchCount == 0) {
      return false;
    }
    findController.previousMatch();
    _reveal();
    return true;
  }

  /// Снимает подсветку найденного.
  void clear() => findController.close();

  void dispose() => findController.dispose();

  /// Показывает текущее совпадение: выделяет его и подводит к нему показ.
  ///
  /// Выделением, а не одним лишь курсором: в просмотрщике курсор скрыт, и без
  /// выделения найденное ничем бы себя не выдало.
  void _reveal() {
    final CodeLineSelection? match = findController.currentMatchSelection;
    if (match == null) {
      return;
    }
    controller.selection = match;
    controller.makePositionCenterIfInvisible(match.start);
  }

  /// Ждёт, пока поиск в изоляте договорит **по нашей строке**.
  ///
  /// Именно по нашей: пока идёт поиск, значение успевает побывать в
  /// промежуточных состояниях — от прошлой строки, от переключённого флажка, —
  /// и «поиск закончился» само по себе ещё не значит, что закончился нужный.
  Future<void> _settled(String text) async {
    bool ready() {
      final CodeFindValue? value = findController.value;
      return value != null && value.option.pattern == text && !value.searching;
    }

    if (ready()) {
      return;
    }

    final Completer<void> done = Completer<void>();
    void listener() {
      if (ready() && !done.isCompleted) {
        done.complete();
      }
    }

    findController.addListener(listener);
    try {
      // Срок — на случай, если изолят не ответит вовсе: команда тогда честно
      // скажет «не нашлось», а не подвиснет молча.
      await done.future.timeout(const Duration(seconds: 5), onTimeout: () {});
    } finally {
      findController.removeListener(listener);
    }
  }
}

/// Экран, по которому можно искать.
///
/// Реализуют его и просмотрщик, и редактор — показ у них общий, значит и поиск
/// один и тот же. Команды поиска спрашивают именно это, а не конкретный экран.
abstract interface class FcSearchable implements ViewportState {
  /// Устойчивое имя: по нему команда поиска узнаёт своё содержимое.
  ///
  /// Просмотрщик и редактор ищут одинаково и пользуются одними командами, но
  /// экземпляры у них разные, и путать их нельзя.
  String get id;

  FcTextFinder get finder;
}
