import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import 'basics_info_provider.dart';
import 'file_info_commands.dart';
import 'file_info_screen.dart';
import 'file_info_view.dart';

/// Сведения об объекте: окно, показ и разметка разделов.
///
/// Содержимого модуль не знает вовсе — его приносят провайдеры сведений,
/// объявленные модулями. Здесь объявлен один из них, `basics`: он описывает
/// поля самой модели и живёт рядом лишь поэтому, а привилегий у него никаких.
///
/// Второе дело модуля — быть **последним просмотрщиком**. За что не взялся
/// никто, берётся он: вместо мусора из байтов человек видит имя, размер, тип и
/// даты. Ради этого текстовый просмотрщик и перестал брать всё подряд.
class FileInfo implements FcFrontendModule {
  const FileInfo();

  @override
  String get id => 'fc.file_info';

  @override
  String get title => 'File info';

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.strings('ru', _russian);
    registry.plurals('ru', _plurals);

    registry.view<FileInfoScreen>((context, state) => FileInfoView(screen: state));

    registry.nodeInfo((context) => BasicsInfoProvider(context.resolve<Strings>()));

    registry.command((context) => FileInfoCommand());

    // Обе привычки настоящие: `Cmd-I` с макоси, `Alt-Enter` из коммандеров.
    registry.binding(KeyBinding('Cmd-I', FileInfoCommand.commandId));
    registry.binding(KeyBinding('Alt-Enter', FileInfoCommand.commandId));

    registry.viewer(
      ViewerSpec(
        id: FileInfoScreen.viewerId,
        title: 'Info',
        // Ниже всех: сведения показывают то, за что не взялся никто.
        priority: -1000,
        // Берётся за всё, включая каталоги: о них тоже есть что сказать, и в
        // быстром просмотре это лучше слова «Directory».
        accepts: (entry, type) => true,
        open:
            (request) async => FileInfoScreen(
              app: request.app,
              entries: [request.entry],
              contentOf: request.contentFor,
              place: request.place,
            ),
      ),
    );
  }
}

/// Русские строки окна сведений.
/// Заголовок окна, когда сведения о нескольких объектах сразу.
const Map<String, PluralForms> _plurals = {'{n} items': (one: '{n} объект', few: '{n} объекта', many: '{n} объектов')};

const Map<String, String> _russian = {
  'File info': 'Сведения о файле',
  'Info': 'Сведения',
  'Everything known about the object under the cursor': 'Всё, что известно об объекте под курсором',

  // Разделы.
  'General': 'Основное',
  'Dates': 'Даты',
  'Access': 'Доступ',
  'Link': 'Ссылка',
  'Selection': 'Выбранное',
  'Contents': 'Содержимое',
  'Error': 'Ошибка',

  // Строки.
  'Name': 'Имя',
  'Path': 'Путь',
  'Type': 'Тип',
  'Extension': 'Расширение',
  'Size': 'Размер',
  'Where': 'Источник',
  'Modified': 'Изменён',
  'Created': 'Создан',
  'Accessed': 'Открыт',
  'Permissions': 'Права',
  'Mode': 'Восьмеричные права',
  'Points to': 'Ведёт на',
  'Target': 'Цель',
  'Items': 'Объектов',
  'Directories': 'Каталогов',

  // Значения.
  'Parent directory': 'Родительский каталог',
  'Directory': 'Каталог',
  'File': 'Файл',
  'Link to a directory': 'Ссылка на каталог',
  'unknown': 'неизвестно',
  'directory': 'каталог',

  // Кнопка подсчёта размера.
  'Calculate': 'Посчитать',
  'Counting…': 'Считаю…',
};
