import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import 'history_command.dart';
import 'history_service.dart';
import 'history_settings.dart';
import 'undo_command.dart';
import 'undo_work.dart';

/// История файловых работ и отмена последней.
///
/// Выключишь модуль — и журнал не ведётся вовсе: ядру о нём не говорят, а
/// `Cmd-Z` не привязан ни к чему (`docs/spec/operation-history.md`, §5).
class OperationHistoryModule implements FcBackendModule, FcFrontendModule {
  const OperationHistoryModule();

  @override
  String get id => 'fc.history';

  @override
  String get title => 'Operation history';

  /// Ядровая половина одна — сама отмена: она ходит по дереву, а дерево живёт
  /// здесь (`docs/spec/client-server.md`, §5.4).
  @override
  void installBackend(BackendRegistry registry) {
    registry.strings('ru', _coreRussian);
    registry.operation(
      HistoryOperations.undo,
      (services) =>
          UndoWork(strings: services.resolve<Strings>(), registry: services.resolve<ProviderRegistry>()).operation(),
    );
  }

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.strings('ru', _russian);
    registry.plurals('ru', _plurals);

    final settings = registry.settings;
    HistorySettings settingsOf() => settings.section(HistorySettings.new);

    registry.service<OperationHistory>((services) => OperationHistoryService(settings: settingsOf));
    registry.command((context) => UndoCommand(context.resolve<OperationHistory>()));
    registry.command((context) => ShowHistoryCommand(context.resolve<OperationHistory>()));

    // Панельная клавиша: в редакторе, в поле ввода и в терминале `Cmd-Z`
    // принадлежит экрану — там отменяют набранное, а не файловую работу.
    registry.binding(KeyBinding('Cmd-Z', UndoCommand.commandId, context: KeyContext.panel));

    registry.settingsSchema(() {
      final strings = registry.services.resolve<Strings>();
      return SettingsSchema([
        SettingsField.integer(
          'depth',
          defaultValue: HistorySettings.defaultDepth,
          title: strings.tr('Operations remembered'),
          unit: strings.tr('entries'),
          min: HistorySettings.minDepth,
          max: HistorySettings.maxDepth,
          description: strings.tr('History lives one session: between runs the disk changes without us'),
          read: () => settingsOf().depth,
          write: (value) => settingsOf().depth = value,
        ),
      ], save: settings.save);
    });
  }
}

/// Русские строки ядровой половины: вехи самой отмены.
const Map<String, String> _coreRussian = {
  'Undoing…': 'Отмена…',
  '{path} changed since then': '{path} с тех пор изменился',
};

const Map<String, String> _russian = {
  'Operation history': 'История операций',
  'What the application did to files this session': 'Что приложение сделало с файлами за этот сеанс',
  'Filter operations': 'Отбор по работам',
  'Only the newest operation can be undone': 'Отменяется только последняя работа',
  'still running': 'ещё идёт',
  'undone': 'отменена',

  'Undo': 'Отменить',
  'Undo the last file operation, if it can be undone': 'Отменить последнюю файловую работу, если это возможно',
  'Undo failed': 'Отменить не вышло',
  'This work cannot be undone': 'Эту работу отменить нельзя',
  'Nothing to undo': 'Отменять нечего',
  'Operations remembered': 'Помнить работ',
  'History lives one session: between runs the disk changes without us':
      'История живёт сеанс: между запусками диск меняется без нас',

  // Причины, по которым отменить нельзя, — их называет работа.
  'nothing to undo': 'ничего ещё не делали',
  'the work is still running': 'работа ещё идёт',
  'this work changed nothing': 'эта работа ничего не изменила',
  'overwritten': 'прежнее содержимое перезаписано',
  'deleted permanently': 'удалено мимо корзины',
  'merged into an existing folder': 'перенос слиянием обратного действия не имеет',
  'part of the source stayed behind': 'часть источника осталась на месте',
  'too many objects to remember': 'объектов слишком много: журнал не поместился',
};

const Map<String, PluralForms> _plurals = {
  '{n} objects': (one: '{n} объект', few: '{n} объекта', many: '{n} объектов'),
  'delete {n} objects': (one: 'удалить {n} объект', few: 'удалить {n} объекта', many: 'удалить {n} объектов'),
  'move {n} objects back': (one: 'вернуть {n} объект', few: 'вернуть {n} объекта', many: 'вернуть {n} объектов'),
  'return {n} objects from Trash': (
    one: 'достать {n} объект из корзины',
    few: 'достать {n} объекта из корзины',
    many: 'достать {n} объектов из корзины',
  ),
};
