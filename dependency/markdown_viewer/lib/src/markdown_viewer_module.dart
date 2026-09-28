import 'dart:convert';

import 'package:fc_api/fc_api.dart';
import 'package:fc_markdown_kit/fc_markdown_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import 'markdown_viewer_commands.dart';
import 'markdown_viewer_screen.dart';
import 'markdown_viewer_settings.dart';
import 'markdown_viewer_view.dart';

/// Просмотрщик markdown — один из.
///
/// Выключите его, и `.md` снова откроет текстовый просмотрщик: он перечисляет
/// `md` среди своих расширений и остаётся запасным. Это и есть проверка того,
/// что возможность приносит модуль (`docs/spec/markdown-viewer.md`, §3).
class MarkdownViewer implements FcFrontendModule {
  const MarkdownViewer();

  /// Расширения, за которые берётся.
  static const Set<String> extensions = {'md', 'markdown', 'mdown', 'mkd'};

  @override
  String get id => 'fc.markdown_viewer';

  @override
  String get title => 'Markdown viewer';

  @override
  void installFrontend(FrontendRegistry registry) {
    // Словарь пакета показа подмешивается к своему: строки у него свои, а
    // реестра строк у библиотеки нет и быть не должно.
    registry.strings('ru', {...markdownKitRussian, ..._russian});

    registry.view<MarkdownViewerScreen>((context, state) => MarkdownViewerView(screen: state));

    final settings = registry.settings;
    MarkdownViewerSettings settingsOf() => settings.section(MarkdownViewerSettings.new);

    registry.settingsSchema(() {
      final strings = registry.services.resolve<Strings>();

      return SettingsSchema([
        SettingsField.flag(
          'startFormatted',
          defaultValue: true,
          title: strings.tr('Open markdown formatted'),
          read: () => settingsOf().startFormatted,
          write: (value) => settingsOf().startFormatted = value,
        ),
        SettingsField.integer(
          'maxFileSize',
          defaultValue: MarkdownViewerSettings.defaultMaxFileSize,
          title: strings.tr('Largest document to open'),
          unit: strings.tr('bytes'),
          min: 1024,
          max: 64 * 1024 * 1024,
          read: () => settingsOf().maxFileSize,
          write: (value) => settingsOf().maxFileSize = value,
        ),
      ], save: settings.save);
    });

    registry.viewer(
      ViewerSpec(
        id: MarkdownViewerScreen.viewerId,
        title: 'Markdown',
        // Выше текстового (−100), ниже картинок (100). Текстовый перечисляет
        // `md` среди своих расширений, и без приоритета он забрал бы файл
        // первым; трогать его список незачем — он нам запасной.
        priority: 50,
        accepts:
            (entry, type) =>
                !entry.isDirectory && !entry.isParent && extensions.contains(extensionOf(entry.name).toLowerCase()),
        open: (request) => _open(request, settingsOf(), settings.save, _optional<SystemOpener>(registry.services)),
      ),
    );

    registry.command((context) => ToggleMarkdownFormatCommand());

    // `F5` — та же клавиша и тот же смысл, что у вектора и у будущих
    // форматтеров. Раздел свой: спор считается по клавише **и** контексту, и в
    // разделе текста два `F5` выглядели бы спором, которого нет (§8).
    registry.binding(
      KeyBinding.inState<MarkdownViewerScreen>(
        'F5',
        ToggleMarkdownFormatCommand.commandId,
        context: KeyContext.markdownViewer,
      ),
    );
  }

  /// Служба, без которой модуль умеет обойтись; null — её никто не объявил.
  static T? _optional<T>(FcServices services) {
    final found = services.resolveAll<T>();

    return found.isEmpty ? null : found.first;
  }

  /// Прочитать файл и отдать показ.
  static Future<ViewerContent> _open(
    ViewerRequest request,
    MarkdownViewerSettings settings,
    void Function() onSettingsChanged,
    SystemOpener? openWith,
  ) async {
    final entry = request.entry;
    if (entry.size > settings.maxFileSize) {
      // Отказ, а не начало файла: показывать кусок и называть его документом —
      // значит врать о содержимом.
      throw ViewerRefused(
        request.app.strings.tr(
          'Document is too large: {size}, limit is {limit}',
          args: {'size': formatBytesLong(entry.size), 'limit': formatBytesLong(settings.maxFileSize)},
        ),
      );
    }

    final bytes = <int>[];
    await for (final chunk in request.content.read()) {
      // Курсор в быстром просмотре мог уйти дальше: дочитывать незачем.
      await request.checkpoint();
      bytes.addAll(chunk);
    }
    await request.checkpoint();

    final source = utf8.decode(bytes, allowMalformed: true);
    if (_isBinary(bytes)) {
      // Имя обещало разметку, а внутри двоичное: пусть покажет тот, кто умеет
      // рассказать о таком файле.
      throw const ViewerDeclined();
    }

    return MarkdownViewerScreen(
      entry: entry,
      document: FcMarkdownDocument.parse(source),
      settings: settings,
      onSettingsChanged: onSettingsChanged,
      place: request.place,
      openWith: openWith,
    );
  }

  /// Двоичное ли это — по нулевому байту в начале.
  ///
  /// Того же простого признака держится и текстовый просмотрщик: текст нулей не
  /// содержит, а разбирать кодировки ради отказа незачем.
  static bool _isBinary(List<int> bytes) {
    final head = bytes.length < 1024 ? bytes.length : 1024;
    for (var i = 0; i < head; i++) {
      if (bytes[i] == 0) {
        return true;
      }
    }

    return false;
  }
}

/// Русские строки просмотра markdown.
const Map<String, String> _russian = {
  'Markdown viewer': 'Markdown',
  'markdown|Format': 'Свёрстано',
  'Raw': 'Исходник',
  'Show the document formatted or as it is written': 'Показать документ свёрстанным или так, как он написан',

  // Отказы.
  'Document is too large: {size}, limit is {limit}': 'Документ слишком велик: {size}, предел — {limit}',

  // Настройки.
  'Open markdown formatted': 'Открывать markdown свёрстанным',
  'Largest document to open': 'Наибольший открываемый документ',
  'bytes': 'байт',
};
