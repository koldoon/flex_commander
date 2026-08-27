import 'dart:convert';

import 'package:fc_api/fc_api.dart';
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
class TextViewer implements FcModule {
  const TextViewer();

  /// Поиск: команды общие с редактором, а идентификаторы свои — в панелях за
  /// `F7` стоит своя команда, и путать их незачем.
  static const String findCommandId = 'text.find';
  static const String findNextCommandId = 'text.findNext';
  static const String findPreviousCommandId = 'text.findPrevious';

  @override
  String get id => 'fc.text_viewer';

  @override
  String get title => 'Text viewer';

  @override
  void install(FcRegistry registry) {
    registry.view<TextViewerScreen>((context, state) => TextViewerView(screen: state));

    // Область забирается **сейчас**, пока идёт установка: позже имя раздела
    // уже неизвестно, и настройки уехали бы в чужой.
    final settings = registry.settings;
    TextViewerSettings settingsOf() => settings.section(TextViewerSettings.new);

    registry.settingsSchema(
      () => SettingsSchema([
        SettingsField.flag(
          'wordWrap',
          title: 'Wrap long lines',
          read: () => settingsOf().wordWrap,
          write: (value) => settingsOf().wordWrap = value,
        ),
        SettingsField.flag(
          'showLineNumbers',
          title: 'Show line numbers',
          read: () => settingsOf().showLineNumbers,
          write: (value) => settingsOf().showLineNumbers = value,
        ),
        SettingsField.integer(
          'maxFileSize',
          title: 'Largest file to open',
          unit: 'bytes',
          min: 1024,
          max: 100 * 1024 * 1024,
          read: () => settingsOf().maxFileSize,
          write: (value) => settingsOf().maxFileSize = value,
        ),
      ], save: settings.save),
    );

    registry.viewer(
      ViewerSpec(
        id: TextViewerScreen.viewerId,
        title: 'Text',
        // Последний в очереди и берётся за всё: байты показать можно всегда.
        // Когда появится модуль сведений о файле, последним станет он, а здесь
        // останется «похоже на текст» — правка ровно в этой строке.
        priority: -100,
        accepts: (node, type) => true,
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
    final node = request.node;
    final source = node.provider;
    if (source is! FileContentProvider) {
      throw ViewerRefused('No content here to show');
    }
    if (node.size > settings.maxFileSize) {
      // Отказ, а не начало файла: показывать кусок и называть его файлом —
      // значит врать о содержимом.
      throw ViewerRefused(
        'File is too large: ${formatBytesLong(node.size)}, limit is ${formatSize(settings.maxFileSize)}',
      );
    }

    final bytes = <int>[];
    await for (final chunk in await (source as FileContentProvider).openRead(node)) {
      // Курсор в быстром просмотре мог уйти дальше: дочитывать незачем.
      await request.checkpoint();
      bytes.addAll(chunk);
    }
    await request.checkpoint();

    return TextViewerScreen(
      node: node,
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
