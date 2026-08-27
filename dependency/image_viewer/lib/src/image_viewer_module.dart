import 'package:fc_api/fc_api.dart';

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
class ImageViewer implements FcModule {
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
  void install(FcRegistry registry) {
    registry.view<ImageViewerScreen>((context, state) => ImageViewerView(screen: state));

    final settings = registry.settings;
    ImageViewerSettings settingsOf() => settings.section(ImageViewerSettings.new);

    registry.settingsSchema(
      () => SettingsSchema([
        SettingsField.flag(
          'fitToWindow',
          title: 'Fit images into the window',
          read: () => settingsOf().fitToWindow,
          write: (value) => settingsOf().fitToWindow = value,
        ),
        SettingsField.integer(
          'maxFileSize',
          title: 'Largest image to open',
          unit: 'bytes',
          min: 1024,
          max: 1024 * 1024 * 1024,
          read: () => settingsOf().maxFileSize,
          write: (value) => settingsOf().maxFileSize = value,
        ),
        SettingsField.integer(
          'maxPixels',
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
            (node, type) =>
                node is FileNode && node is! DirectoryNode && extensions.contains(node.extension.toLowerCase()),
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
    final node = request.node;
    final document = await ImageDocument.read(node, settings, checkpoint: request.checkpoint);
    // Распаковать сразу: показ должен появиться картинкой, а не пустым местом,
    // которое через миг сменится картинкой.
    await document.warmUp();

    return ImageViewerScreen(
      node: node,
      document: document,
      settings: settings,
      onSettingsChanged: onSettingsChanged,
      place: request.place,
      // Соседи — один раз при открытии: каталог за это время не изменится, а
      // перечитывать его на каждую стрелку значило бы ходить по диску вместо
      // показа.
      siblings: await _siblingsOf(node),
    );
  }

  /// Картинки того же каталога, в порядке источника.
  ///
  /// Пусто — листать нечем: узел без каталога (результаты поиска) или каталог
  /// не прочитался. Это не ошибка показа: картинка уже открыта.
  static Future<List<FsNode>> _siblingsOf(FsNode node) async {
    final directory = node.parentDirectory;
    if (directory == null) {
      return const [];
    }
    try {
      final children = await node.provider.listChildren(directory);
      return [
        for (final child in children)
          if (child is FileNode && extensions.contains(child.extension.toLowerCase())) child,
      ];
    } on Object {
      return const [];
    }
  }
}
