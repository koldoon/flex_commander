import 'package:flutter/foundation.dart';

import 'app_command.dart';
import 'key_combination.dart';

/// Действия приложения и клавиши за ними — то, чем оперируют модули и виджеты.
///
/// Интерфейс, а не реестр: тот, кто ставит команду или спрашивает, что висит на
/// `F5`, не должен знать, как устроено хранение прототипов и запусков. Реестр
/// ядра ([CommandRegistry]) — его реализация, и он же делает то, что наружу не
/// отдаётся: привязывает себя к приложению и создаёт прототипы.
///
/// [Listenable]: набор команд и список открытых окон меняются по ходу работы —
/// модуль может поставить команду после запуска, — и нижняя панель с окнами
/// команд перерисовываются по уведомлению.
abstract interface class CommandService implements Listenable {
  /// Команды в порядке установки — то, что увидит список команд и справка.
  List<AppCommand> get installed;

  /// Все привязки в порядке приоритета.
  List<KeyBinding> get bindings;

  /// Ставит команду. Фабрика зовётся на каждый запуск: команда хранит
  /// состояние исполнения, поэтому экземпляр у запуска свой.
  void install(AppCommandFactory factory);

  /// Закрепляет комбинацию за командой. Более ранние привязки имеют приоритет.
  void bind(KeyBinding binding);

  /// Снимает все привязки команды — например, при переназначении клавиш.
  void unbind(String commandId);

  /// Чем вызывается команда: для справки и настроек.
  List<KeyBinding> bindingsOf(String commandId);

  /// Прототип команды: название и выполнимость. Для работы нужен [create].
  AppCommand? find(String id);

  /// Команда, закреплённая за комбинацией прямо сейчас.
  AppCommand? commandFor(KeyCombination combination);

  /// Привязка, которая сработает по этой комбинации прямо сейчас.
  KeyBinding? bindingFor(KeyCombination combination);

  /// Находит подходящую команду и выполняет её. false — ничего не подошло,
  /// и нажатие уходит дальше по дереву виджетов.
  bool dispatch(KeyCombination combination);

  /// Запускает команду по идентификатору — с клавиатуры, кнопкой, из меню.
  /// Результат всюду одинаковый.
  bool run(String commandId, [CommandInvocation invocation = const CommandInvocation()]);

  /// Создаёт экземпляр команды и связывает его с запуском, но не выполняет:
  /// так её получают те, кто задаёт параметры сам.
  AppCommand? create(String commandId);

  /// Можно ли выполнить команду прямо сейчас.
  bool isExecutable(AppCommand command, [CommandInvocation invocation = const CommandInvocation()]);
}
