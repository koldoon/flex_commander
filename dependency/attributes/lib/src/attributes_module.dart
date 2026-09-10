import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import 'attribute_edits.dart';
import 'attributes_command.dart';
import 'attributes_operation.dart';
import 'xattr_info_provider.dart';

/// Правка атрибутов: команда и окно на экране, работа — в ядре.
///
/// Зовётся не `FileAttributes`: так называется **значение** в `fc_api` — то,
/// что показывает колонка «Атрибуты». Два имени про разное однажды сойдутся в
/// одном файле, и разбирать их придётся приставками к импортам.
///
/// Один класс на обе стороны: половины у модуля разные, а модуль один.
/// Выключен — пропадают команда, клавиша и работа; примитивы провайдеров
/// остаются и никому не мешают.
class AttributeEditing implements FcBackendModule, FcFrontendModule {
  const AttributeEditing();

  @override
  String get id => 'fc.attributes';

  @override
  String get title => 'File attributes';

  @override
  void installBackend(BackendRegistry registry) {
    registry.strings('ru', _coreRussian);
    // Работа рождается там, где живут источники: обход, прогресс и вопросы —
    // по эту сторону границы.
    registry.operation(
      AttributeOperations.apply,
      (services) => AttributesApply(services.resolve<Strings>()).operation(),
    );
  }

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.strings('ru', _russian);
    registry.plurals('ru', _plurals);

    // Сведения дополняются нашим разделом — и окно о нас ничего не знает:
    // рассказывает о расширенных атрибутах тот, кто с ними и работает.
    registry.nodeInfo((context) => XattrInfoProvider(context.resolve<Strings>()));

    registry.command((context) => AttributesCommand());
    // Привычка Far Manager: там за этим сочетанием ровно атрибуты файла. На
    // macOS оно свободно — пометить всё там `Cmd-A`.
    registry.binding(KeyBinding('Ctrl-A', AttributesCommand.commandId));
    // Второе — ради Windows и Linux: там `Cmd-A` разбирается **как** `Ctrl-A`,
    // и первое сочетание достаётся пометке «выделить всё», которая старше и
    // привычнее. Тот же приём, которым живёт показ скрытых объектов: основное
    // сочетание одно, второе — для платформы, где первое занято.
    registry.binding(KeyBinding('Cmd-Shift-I', AttributesCommand.commandId));
  }
}

/// Строки ядра: их пишет работа, а показывает окно.
const Map<String, String> _coreRussian = {'Changing attributes…': 'Правка атрибутов…'};

const Map<String, String> _russian = {
  'File attributes': 'Атрибуты файла',
  'Attributes': 'Атрибуты',
  'Change permissions, dates, owner and extended attributes': 'Права, даты, владелец и расширенные атрибуты',
  'Changing attributes…': 'Правка атрибутов…',
  'Changing attributes failed': 'Не вышло поменять атрибуты',
  'Apply': 'Применить',
  'User': 'Владелец',
  'Group': 'Группа',
  'Others': 'Остальные',
  'Special': 'Особые',
  'read': 'чтение',
  'write': 'запись',
  'exec': 'запуск',
  'Octal': 'Восьмеричные',
  'mixed': 'по-разному',
  'Owner': 'Владелец',
  'user': 'пользователь',
  'group': 'группа',
  'Modified': 'Изменён',
  'Accessed': 'Открыт',
  'Extended attributes': 'Расширенные атрибуты',
  'binary': 'двоичное',
  'Apply to': 'Применить к',
  'Remove': 'Убрать',
  'Add': 'Добавить',
  'name': 'имя',
  'value': 'значение',
  'Recursive': 'Внутрь каталогов',
  'files and directories': 'файлы и каталоги',
  'only files': 'только файлы',
  'only directories': 'только каталоги',
  'Wrong date: {text}': 'Негодная дата: {text}',
  'Unknown user: {name}': 'Неизвестный пользователь: {name}',
};

/// Ключ множественного — форма `other`: та, что написана в коде вторым доводом.
const Map<String, PluralForms> _plurals = {
  '{n} items': (one: '{n} объект', few: '{n} объекта', many: '{n} объектов'),
  '{n} bytes': (one: '{n} байт', few: '{n} байта', many: '{n} байт'),
  '{n} attributes': (one: '{n} атрибут', few: '{n} атрибута', many: '{n} атрибутов'),
};
