import 'dart:convert';

import 'dart:typed_data';

import 'package:fc_api/fc_api.dart';
import 'package:fc_content_types/fc_content_types.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_text_kit/fc_text_kit.dart';

import 'text_document.dart';
import 'text_viewer_commands.dart';
import 'text_viewer_screen.dart';
import 'text_viewer_settings.dart';
import 'text_viewer_view.dart';

/// Просмотрщик текста — один из.
///
/// Про то, какой клавишей открывают и куда ставят показ, этот модуль не знает
/// вовсе: он объявляет `ViewerSpec` в общий реестр, как модуль архива
/// объявляет провайдер. Спрашивает объявленное оболочка просмотра
/// (`fc_viewer`), и связывает их собранное приложение, а не зависимость
/// пакетов.
///
/// Выключите его — пропадёт **только текст**: `F3` останется на месте и
/// откроет то, за что возьмётся кто-то другой.
class TextViewer implements FcFrontendModule {
  const TextViewer();

  /// Поиск: команды общие с редактором, а идентификаторы свои — в панелях за
  /// `F7` стоит своя команда, и путать их незачем.
  static const String findCommandId = 'text.find';
  static const String findNextCommandId = 'text.findNext';
  static const String findPreviousCommandId = 'text.findPrevious';

  /// Расширения, по которым текст узнают **не читая**.
  ///
  /// Список остался, но решает он не всё: расширений у текста больше, чем можно
  /// перечислить — `.as`, `.pro`, `.gradle`, — и такой файл живьём открывался
  /// окном сведений вместо кода. Поэтому берёмся мы за любой файл, а двоичное
  /// отсеиваем по **началу**, уже открыв (§11.2 `content-types.md`): имя
  /// обманывает, начало файла нет.
  ///
  /// Раньше текст брался за **всё**: показать байты можно всегда, и файла,
  /// который нечем открыть, быть не могло. Теперь последним стоит модуль
  /// сведений — он расскажет про `.bin` куда больше, чем мусор из байтов.
  static const Set<String> extensions = {
    'txt',
    'md',
    'markdown',
    'rst',
    'log',
    'text',
    'dart',
    'js',
    'ts',
    'jsx',
    'tsx',
    'py',
    'rb',
    'go',
    'rs',
    'java',
    'kt',
    'swift',
    'c',
    'h',
    'cpp',
    'hpp',
    'cc',
    'm',
    'mm',
    'cs',
    'php',
    'lua',
    'pl',
    'sh',
    'bash',
    'zsh',
    'fish',
    'ps1',
    'bat',
    'cmd',
    'json',
    'yaml',
    'yml',
    'toml',
    'ini',
    'conf',
    'cfg',
    'properties',
    'env',
    'plist',
    'xml',
    'html',
    'htm',
    'css',
    'scss',
    'less',
    'svg',
    'csv',
    'tsv',
    'sql',
    'graphql',
    'proto',
    'gitignore',
    'gitattributes',
    'dockerfile',
    'makefile',
    'lock',
    'patch',
    'diff',
    'srt',
    'vtt',
  };

  /// Скрипт по сигнатуре `#!` — имя типа из таблицы служб типов.
  static const String _script = 'script';

  /// Имена без расширения, которые всё равно текст: `Makefile`, `LICENSE`.
  ///
  /// Каталог отсеивается **отдельной** строкой: расширения у него обычно нет,
  /// то есть он выглядел бы текстом без имени.
  static bool looksLikeText(FileEntry entry) {
    if (entry.isDirectory || entry.isParent) {
      return false;
    }
    final extension = extensionOf(entry.name).toLowerCase();
    if (extension.isEmpty) {
      // Без расширения — почти всегда текст: `Makefile`, `LICENSE`, `README`,
      // `.gitignore`.
      return true;
    }
    return extensions.contains(extension);
  }

  /// Стоит ли и пробовать: за файл берёмся, за каталог — нет.
  ///
  /// Известный тип решает сразу: текст — берёмся, картинка или архив — нет,
  /// читать их незачем. Неизвестный — берёмся и смотрим начало сами
  /// ([_isBinary]); ошиблись — говорим [ViewerDeclined], и очередь идёт дальше.
  ///
  /// Скрипт — тоже текст: группа у него «исполняемое», но показывают его
  /// строками.
  static bool canBeText(FileEntry entry, [ContentType? type]) {
    if (entry.isDirectory || entry.isParent) {
      return false;
    }
    if (type == null) {
      return true;
    }
    return type.group == ContentGroup.text || type.group == ContentGroup.binary || type.id == _script;
  }

  @override
  String get id => 'fc.text_viewer';

  @override
  String get title => 'Text viewer';

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.strings('ru', _russian);
    registry.plurals('ru', _plurals);

    registry.view<TextViewerScreen>((context, state) => TextViewerView(screen: state));

    // Область забирается **сейчас**, пока идёт установка: позже имя раздела
    // уже неизвестно, и настройки уехали бы в чужой.
    final settings = registry.settings;
    TextViewerSettings settingsOf() => settings.section(TextViewerSettings.new);

    registry.settingsSchema(() {
      final strings = registry.services.resolve<Strings>();
      return SettingsSchema([
        SettingsField.flag(
          'wordWrap',
          defaultValue: false,
          title: strings.tr('Wrap long lines'),
          read: () => settingsOf().wordWrap,
          write: (value) => settingsOf().wordWrap = value,
        ),
        SettingsField.flag(
          'showLineNumbers',
          defaultValue: false,
          title: strings.tr('Show line numbers'),
          read: () => settingsOf().showLineNumbers,
          write: (value) => settingsOf().showLineNumbers = value,
        ),
        SettingsField.integer(
          'maxFileSize',
          defaultValue: TextViewerSettings.defaultMaxFileSize,
          title: strings.tr('Largest file to open'),
          unit: strings.tr('bytes'),
          min: 1024,
          max: 100 * 1024 * 1024,
          read: () => settingsOf().maxFileSize,
          write: (value) => settingsOf().maxFileSize = value,
        ),
      ], save: settings.save);
    });

    registry.viewer(
      ViewerSpec(
        id: TextViewerScreen.viewerId,
        title: 'Text',
        // Ниже картинок, но выше сведений: сведения стоят последними и
        // берутся за то, за что не взялся никто.
        priority: -100,
        accepts: (entry, type) => canBeText(entry, type),
        open: (request) => _open(request, settingsOf(), settings.save),
      ),
    );

    registry.command((context) => ToggleWordWrapCommand());
    registry.command((context) => ToggleLineNumbersCommand());
    registry.command((context) => CopySelectionCommand(registry.services.resolve<ClipboardService>()));

    // Поиск — общий с редактором: экран и идентификаторы приходят отсюда, а
    // сами команды одни на двоих (`fc_text_kit`).
    registry.command((context) => FcFindTextCommand(id: findCommandId, screenId: TextViewerScreen.screenId));
    registry.command((context) => FcFindNextCommand(id: findNextCommandId, screenId: TextViewerScreen.screenId));
    registry.command(
      (context) => FcFindPreviousCommand(id: findPreviousCommandId, screenId: TextViewerScreen.screenId),
    );

    // Клавиши действуют при показанном тексте — где бы он ни стоял: во весь
    // экран или в быстром просмотре. `inState` находит его сквозь хозяина.
    registry.binding(KeyBinding.inState<TextViewerScreen>('F2', ToggleWordWrapCommand.commandId));
    registry.binding(KeyBinding.inState<TextViewerScreen>('F9', ToggleLineNumbersCommand.commandId));
    registry.binding(KeyBinding.inState<TextViewerScreen>('F7', findCommandId));
    registry.binding(KeyBinding.inState<TextViewerScreen>('Cmd-F', findCommandId));
    registry.binding(KeyBinding.inState<TextViewerScreen>('Shift-F7', findNextCommandId));
    registry.binding(KeyBinding.inState<TextViewerScreen>('Cmd-G', findNextCommandId));
    registry.binding(KeyBinding.inState<TextViewerScreen>('Shift-Cmd-G', findPreviousCommandId));
    registry.binding(KeyBinding.inState<TextViewerScreen>('Cmd-C', CopySelectionCommand.commandId));

    // Стрелок, страниц и `Home` здесь нет нарочно: прокрутку и выделение
    // забрал себе показ — он же берёт фокус.
  }

  /// Прочитать файл и отдать показ.
  ///
  /// Отказ — [ViewerRefused] с причиной словами: показывает её то место, куда
  /// открывали, а решает — тот, кто знает свой предел.
  static Future<ViewerContent> _open(
    ViewerRequest request,
    TextViewerSettings settings,
    void Function() onSettingsChanged,
  ) async {
    final entry = request.entry;
    if (entry.size > settings.maxFileSize) {
      // Про **текст** отказ говорится словами: большой журнал человек открыть и
      // хотел, и предел ему стоит увидеть. А про файл, который текстом и не
      // выглядит, говорить нечего: мы даже не знаем, текст ли это, — читать
      // ради этого гигабайт незачем, и пусть покажет тот, кто расскажет о нём
      // не читая.
      if (!looksLikeText(entry)) {
        throw const ViewerDeclined();
      }
      // Отказ, а не начало файла: показывать кусок и называть его файлом —
      // значит врать о содержимом.
      throw ViewerRefused(
        request.app.strings.tr(
          'File is too large: {size}, limit is {limit}',
          args: {'size': formatBytesLong(entry.size), 'limit': formatBytesLong(settings.maxFileSize)},
        ),
      );
    }

    final bytes = <int>[];
    var judged = false;
    await for (final chunk in request.content.read()) {
      // Курсор в быстром просмотре мог уйти дальше: дочитывать незачем.
      await request.checkpoint();
      bytes.addAll(chunk);
      // Двоичное отсеивается по началу и **до** дочитывания: тянуть гигабайт,
      // чтобы потом сказать «это не текст», незачем.
      if (!judged && bytes.length >= ContentTypeTable.headSize) {
        judged = true;
        if (_isBinary(bytes)) {
          throw const ViewerDeclined();
        }
      }
    }
    await request.checkpoint();

    // Файл кончился раньше головы — судим по тому, что есть.
    if (!judged && _isBinary(bytes)) {
      throw const ViewerDeclined();
    }

    return TextViewerScreen(
      entry: entry,
      place: request.place,
      text: TextDocument.parse(utf8.decode(bytes, allowMalformed: true)).text,
      wordWrap: settings.wordWrap,
      showLineNumbers: settings.showLineNumbers,
      onWrapChanged: (value) {
        settings.wordWrap = value;
        onSettingsChanged();
      },
      onLineNumbersChanged: (value) {
        settings.showLineNumbers = value;
        onSettingsChanged();
      },
    );
  }
}

/// Текст ли это — по началу файла, тем же правилом, что у службы типов.
///
/// Своего правила здесь нет нарочно: два ответа на вопрос «это текст?»
/// разошлись бы молча, и файл открывался бы по `F3` иначе, чем показывает его
/// иконка (`docs/spec/content-types.md`, §9).
bool _isBinary(List<int> bytes) {
  final head =
      bytes.length > ContentTypeTable.headSize
          ? Uint8List.fromList(bytes.sublist(0, ContentTypeTable.headSize))
          : Uint8List.fromList(bytes);
  return head.isNotEmpty && textOrBinary(head).group == ContentGroup.binary;
}

/// Русские строки просмотра текста.
const Map<String, String> _russian = {
  'Find': 'Найти',
  'Find text': 'Найти текст',
  'Find text in the document': 'Найти строку в показанном тексте',
  'Find Next': 'Найти дальше',
  'Go to the next match': 'Перейти к следующему совпадению',
  'Find Previous': 'Найти раньше',
  'Go to the previous match': 'Перейти к предыдущему совпадению',
  'Text': 'Текст',
  'text to find': 'что найти',
  'Case sensitive': 'Различать регистр',
  'Regular expression': 'Регулярное выражение',
  'Nothing to find': 'Искать нечего',
  'Not a valid expression': 'Это не выражение',
  'Not found: {what}': 'Не найдено: {what}',
  'Match {index} of {count}': 'Совпадение {index} из {count}',
  'Text viewer': 'Просмотр',
  'Copy': 'Копировать',
  'Copy the selected text to the clipboard': 'Скопировать выделенный текст в буфер обмена',
  'Wrap': 'Переносить',
  'Unwrap': 'Не переносить',
  'Wrap long lines in the viewer': 'Переносить длинные строки в просмотрщике',
  'Wrap: On': 'Перенос строк: включён',
  'Wrap: Off': 'Перенос строк: выключен',
  'Line Num': 'Номера',
  'Show line numbers in the viewer': 'Показывать номера строк в просмотрщике',
  'Show line numbers: On': 'Номера строк: показаны',
  'Show line numbers: Off': 'Номера строк: скрыты',
  'File is too large: {size}, limit is {limit}': 'Файл слишком велик: {size}, предел — {limit}',

  // Настройки.
  'Wrap long lines': 'Переносить длинные строки',
  'Show line numbers': 'Показывать номера строк',
  'Largest file to open': 'Наибольший открываемый файл',
  'bytes': 'байт',
};

/// Множественные формы.
const Map<String, PluralForms> _plurals = {
  'Copied {n} characters': (one: 'Скопирован {n} знак', few: 'Скопировано {n} знака', many: 'Скопировано {n} знаков'),
};
