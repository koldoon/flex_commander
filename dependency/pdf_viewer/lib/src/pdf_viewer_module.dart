import 'package:fc_api/fc_api.dart';
import 'package:fc_text_kit/fc_text_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import 'pdf_document.dart';
import 'pdf_viewer_commands.dart';
import 'pdf_viewer_screen.dart';
import 'pdf_viewer_settings.dart';
import 'pdf_viewer_view.dart';

/// Просмотрщик PDF — один из.
///
/// Страницы рисует система (`SystemPdf`), а показ, масштаб и поиск — его
/// (`docs/spec/pdf-viewer.md`). Про `F3` и быстрый просмотр модуль не знает:
/// он объявляет `ViewerSpec` в общий реестр. Выключите его — `.pdf` перестанет
/// открываться страницами, и только он.
class PdfViewer implements FcFrontendModule {
  const PdfViewer();

  @override
  String get id => 'fc.pdf_viewer';

  @override
  String get title => 'PDF viewer';

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.strings('ru', _russian);

    registry.view<PdfViewerScreen>((context, state) => PdfViewerView(screen: state));

    final settings = registry.settings;
    PdfViewerSettings settingsOf() => settings.section(PdfViewerSettings.new);

    registry.settingsSchema(() {
      final strings = registry.services.resolve<Strings>();
      return SettingsSchema([
        SettingsField.flag(
          'wholePage',
          defaultValue: false,
          title: strings.tr('Show the whole page instead of fitting the width'),
          read: () => settingsOf().wholePage,
          write: (value) => settingsOf().wholePage = value,
        ),
        SettingsField.integer(
          'maxFileSize',
          defaultValue: PdfViewerSettings.defaultMaxFileSize,
          title: strings.tr('Largest PDF to open'),
          unit: strings.tr('bytes'),
          min: 1024,
          max: 2 * 1024 * 1024 * 1024,
          read: () => settingsOf().maxFileSize,
          write: (value) => settingsOf().maxFileSize = value,
        ),
      ], save: settings.save);
    });

    // Названные пароли — на весь сеанс: второй `F3` на том же документе и
    // быстрый просмотр после него пароля уже не спрашивают (§15.2).
    final passwords = PdfPasswords();

    registry.viewer(
      ViewerSpec(
        id: PdfViewerScreen.viewerId,
        title: 'PDF',
        // Выше текстового, как картинки: тот берётся за всё, а этот — за своё.
        priority: 100,
        // Каталог отсеивается отдельно: каталог с именем `docs.pdf` иначе
        // сошёл бы за документ.
        accepts:
            (entry, type) => !entry.isDirectory && !entry.isParent && extensionOf(entry.name).toLowerCase() == 'pdf',
        open:
            (request) => _open(
              request,
              settingsOf(),
              settings.save,
              _optional<SystemPdf>(registry.services),
              passwords,
              _optional<Credentials>(registry.services),
            ),
      ),
    );

    registry.command((context) => TogglePdfFitCommand());
    registry.command((context) => TogglePdfTextCommand());
    registry.command((context) => ZoomPdfCommand());
    // Поиск — команды общие с текстом: окно одно, а кто ищет, решает экран —
    // в страницах система, в тексте поле (§9).
    registry.command((context) => FcFindTextCommand(id: _findId, screenId: PdfViewerScreen.viewerId));
    registry.command((context) => FcFindNextCommand(id: _findNextId, screenId: PdfViewerScreen.viewerId));
    registry.command((context) => FcFindPreviousCommand(id: _findPreviousId, screenId: PdfViewerScreen.viewerId));

    // `F2`, `F5` и `F7` — те же клавиши и тот же смысл, что у картинок и
    // markdown: одно дело — одна клавиша во всём приложении.
    registry.binding(
      KeyBinding.inState<PdfViewerScreen>('F2', TogglePdfFitCommand.commandId, context: KeyContext.pdfViewer),
    );
    registry.binding(
      KeyBinding.inState<PdfViewerScreen>('F5', TogglePdfTextCommand.commandId, context: KeyContext.pdfViewer),
    );
    registry.binding(KeyBinding.inState<PdfViewerScreen>('F7', _findId, context: KeyContext.pdfViewer));
    registry.binding(KeyBinding.inState<PdfViewerScreen>('Shift-F7', _findNextId, context: KeyContext.pdfViewer));
    registry.binding(
      KeyBinding.inState<PdfViewerScreen>('Shift-Cmd-G', _findPreviousId, context: KeyContext.pdfViewer),
    );
    // Приближение — и на `+`, и на `=`, как у картинок: разные клавиши, у
    // каждой своё имя.
    for (final (key, id) in [('+', 'pdf.zoom.in.pad'), ('=', 'pdf.zoom.in')]) {
      registry.binding(
        KeyBinding.inState<PdfViewerScreen>(
          key,
          ZoomPdfCommand.commandId,
          id: id,
          parameters: {ZoomPdfCommand.factorParam: PdfViewerScreen.zoomStep},
          context: KeyContext.pdfViewer,
        ),
      );
    }
    registry.binding(
      KeyBinding.inState<PdfViewerScreen>(
        '-',
        ZoomPdfCommand.commandId,
        id: 'pdf.zoom.out',
        parameters: {ZoomPdfCommand.factorParam: 1 / PdfViewerScreen.zoomStep},
        context: KeyContext.pdfViewer,
      ),
    );
  }

  /// Имена команд поиска. Свои: переназначают их отдельно, и экран другой.
  static const String _findId = 'pdf.find';
  static const String _findNextId = 'pdf.findNext';
  static const String _findPreviousId = 'pdf.findPrevious';

  /// Служба, без которой модуль умеет обойтись; null — её никто не объявил.
  static T? _optional<T>(FcServices services) {
    final found = services.resolveAll<T>();
    return found.isEmpty ? null : found.first;
  }

  static Future<ViewerContent> _open(
    ViewerRequest request,
    PdfViewerSettings settings,
    void Function() onSettingsChanged,
    SystemPdf? system,
    PdfPasswords passwords,
    Credentials? credentials,
  ) async {
    final document = await PdfDocument.read(
      request.entry,
      request.content,
      settings,
      system: system,
      checkpoint: request.checkpoint,
      strings: request.app.strings,
      passwords: passwords,
      credentials: credentials,
      mayAsk: request.place == ViewerPlace.fullscreen,
    );
    return PdfViewerScreen(
      entry: request.entry,
      document: document,
      settings: settings,
      onSettingsChanged: onSettingsChanged,
      place: request.place,
    );
  }
}

/// Русские строки просмотра PDF.
const Map<String, String> _russian = {
  'PDF viewer': 'PDF',
  'Page {page} of {count}': 'Страница {page} из {count}',
  'Fit width': 'По ширине',
  'Whole page': 'Страница целиком',
  'Fit pages to the window width or show the whole page':
      'Вписать страницы по ширине окна или показать страницу целиком',
  'Pages': 'Страницы',
  'pdf|Text': 'Текст',
  'Show the text of the document instead of its pages': 'Показать текст документа вместо страниц',
  'This PDF has no text — it is probably a scan': 'В этом PDF нет текста — вероятно, это скан',
  'Zoom': 'Масштаб',
  'Zoom the pages in or out': 'Приблизить или отдалить страницы',

  // Отказы.
  'PDF viewing needs the system service — open it with the system (Cmd-O)':
      'Для показа PDF нужна служба системы; откройте файл системой (Cmd-O)',
  'PDF is too large: {size}, limit is {limit} — open it with the system (Cmd-O)':
      'PDF слишком велик: {size}, предел — {limit}; откройте его системой (Cmd-O)',
  'Not a PDF, or the file is damaged (Cmd-O opens it with the system)':
      'Это не PDF или файл повреждён (Cmd-O откроет его системой)',
  'This PDF is password-protected — open it with the system (Cmd-O)':
      'PDF защищён паролем; откройте его системой (Cmd-O)',
  'This PDF is password-protected — press F3 to enter the password':
      'PDF защищён паролем; нажмите F3, чтобы ввести пароль',
  'Password-protected PDF': 'PDF под паролем',

  // Настройки.
  'Show the whole page instead of fitting the width': 'Показывать страницу целиком, а не по ширине',
  'Largest PDF to open': 'Наибольший открываемый PDF',
  'bytes': 'байт',
};
