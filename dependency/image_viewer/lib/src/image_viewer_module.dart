import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import 'image_document.dart';
import 'image_info_provider.dart';
import 'image_viewer_commands.dart';
import 'image_viewer_screen.dart';
import 'image_viewer_settings.dart';
import 'image_viewer_view.dart';

/// Просмотрщик изображений — один из.
///
/// Про то, какой клавишей его открывают и куда ставят показ, модуль не знает
/// вовсе: он объявляет `ViewerSpec` в общий реестр, а выбирает оболочка
/// просмотра. Выключите его — картинки перестанут открываться, и только они.
class ImageViewer implements FcFrontendModule {
  const ImageViewer();

  /// Расширения, за которые берётся. Всё это декодирует сам Flutter (Skia);
  /// `tiff`, `heic` и `avif` он не умеет — на них отказ с предложением открыть
  /// системой.
  static const Set<String> extensions = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'};

  @override
  String get id => 'fc.image_viewer';

  @override
  String get title => 'Image viewer';

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.view<ImageViewerScreen>((context, state) => ImageViewerView(screen: state));

    final settings = registry.settings;
    ImageViewerSettings settingsOf() => settings.section(ImageViewerSettings.new);

    registry.settingsSchema(
      () => SettingsSchema([
        SettingsField.flag(
          'fitToWindow',
          defaultValue: true,
          title: 'Fit images into the window',
          read: () => settingsOf().fitToWindow,
          write: (value) => settingsOf().fitToWindow = value,
        ),
        SettingsField.integer(
          'maxFileSize',
          defaultValue: ImageViewerSettings.defaultMaxFileSize,
          title: 'Largest image to open',
          unit: 'bytes',
          min: 1024,
          max: 1024 * 1024 * 1024,
          read: () => settingsOf().maxFileSize,
          write: (value) => settingsOf().maxFileSize = value,
        ),
        SettingsField.integer(
          'maxPixels',
          defaultValue: ImageViewerSettings.defaultMaxPixels,
          title: 'Largest image to decode',
          unit: 'pixels',
          min: 1000 * 1000,
          max: 512 * 1000 * 1000,
          read: () => settingsOf().maxPixels,
          write: (value) => settingsOf().maxPixels = value,
        ),
      ], save: settings.save),
    );

    registry.viewer(
      ViewerSpec(
        id: ImageViewerScreen.viewerId,
        title: 'Image',
        // Выше текстового: тот стоит последним и берётся за всё, а картинка —
        // за своё, по расширению. Появится Б6 — `accepts` начнёт смотреть на
        // настоящий тип, и `.png`, оказавшийся текстом, перестанет обманывать.
        priority: 100,
        // Каталог отсеивается отдельно: `DirectoryNode` — наследник
        // `FileNode`, и каталог с именем `shots.png` иначе сошёл бы за
        // картинку.
        accepts:
            (entry, type) =>
                !entry.isDirectory && !entry.isParent && extensions.contains(extensionOf(entry.name).toLowerCase()),
        open: (request) => _open(request, settingsOf(), settings.save),
      ),
    );

    // Сведения о картинке — тому окну, которое их показывает. Ему про
    // картинки знать неоткуда, а нам про окно — незачем: между нами общий
    // контракт и ни одной правки в чужом модуле.
    registry.nodeInfo((context) => ImageInfoProvider(settingsOf()));

    registry.command((context) => ToggleImageFitCommand());
    registry.command((context) => ZoomImageCommand());
    registry.command((context) => StepImageCommand(forward: true));
    registry.command((context) => StepImageCommand(forward: false));

    // Клавиши действуют при показанной картинке — где бы она ни стояла: во
    // весь экран или в быстром просмотре. `inState` находит её сквозь хозяина.
    registry.binding(KeyBinding.inState<ImageViewerScreen>('F2', ToggleImageFitCommand.commandId));
    // Приближение — и на `+`, и на `=`: на большинстве раскладок плюс требует
    // Shift, а привычка из браузеров говорит именно про эту клавишу.
    for (final key in ['+', '=']) {
      registry.binding(
        KeyBinding.inState<ImageViewerScreen>(
          key,
          ZoomImageCommand.commandId,
          parameters: {ZoomImageCommand.factorParam: ImageViewerScreen.zoomStep},
        ),
      );
    }
    registry.binding(
      KeyBinding.inState<ImageViewerScreen>(
        '-',
        ZoomImageCommand.commandId,
        parameters: {ZoomImageCommand.factorParam: 1 / ImageViewerScreen.zoomStep},
      ),
    );

    // Стрелки листают каталог, а не возят картинку: возить её мышью удобнее, а
    // вот сто раз выходить в панель ради следующего снимка — нет.
    //
    // Только во весь экран: в быстром просмотре они принадлежат панели, и
    // следующая картинка появляется оттого, что курсор пошёл вниз. Решает это
    // сама команда — привязка объявляется на тип, а мест у него два.
    registry.binding(KeyBinding.inState<ImageViewerScreen>('Right', StepImageCommand.nextCommandId));
    registry.binding(KeyBinding.inState<ImageViewerScreen>('Down', StepImageCommand.nextCommandId));
    registry.binding(KeyBinding.inState<ImageViewerScreen>('Left', StepImageCommand.previousCommandId));
    registry.binding(KeyBinding.inState<ImageViewerScreen>('Up', StepImageCommand.previousCommandId));
  }

  /// Открыть: прочитать, разобрать заголовок и собрать список соседей.
  static Future<ViewerContent> _open(
    ViewerRequest request,
    ImageViewerSettings settings,
    void Function() onSettingsChanged,
  ) async {
    final entry = request.entry;
    final document = await ImageDocument.read(entry, request.content, settings, checkpoint: request.checkpoint);
    // Распаковать сразу: показ должен появиться картинкой, а не пустым местом,
    // которое через миг сменится картинкой.
    await document.warmUp();

    return ImageViewerScreen(
      entry: entry,
      document: document,
      settings: settings,
      onSettingsChanged: onSettingsChanged,
      place: request.place,
      // Соседи — один раз при открытии: каталог за это время не изменится, а
      // перечитывать его на каждую стрелку значило бы ходить по диску вместо
      // показа.
      // Соседи — те, что показаны в панели: список уже на руках и
      // отсортирован так же, как видит человек.
      siblings: [
        for (final sibling in request.siblings)
          if (!sibling.isDirectory && !sibling.isParent && extensions.contains(extensionOf(sibling.name).toLowerCase()))
            sibling,
      ],
      contentOf: request.contentFor,
    );
  }
}
