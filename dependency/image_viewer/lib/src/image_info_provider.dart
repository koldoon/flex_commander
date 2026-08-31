import 'package:fc_api/fc_api.dart';

import 'image_document.dart';
import 'image_viewer_module.dart';
import 'image_viewer_settings.dart';

/// Что просмотрщик картинок знает о файле: размеры и формат.
///
/// Знает он их даром: заголовок разбирается и так — по нему решается, стоит ли
/// вообще распаковывать. Сведениям достаётся то же самое.
///
/// Позже сюда же встанет EXIF: снято тогда-то, тем-то, с такой выдержкой.
class ImageInfoProvider implements NodeInfoProvider {
  const ImageInfoProvider(this.settings);

  final ImageViewerSettings settings;

  @override
  String get id => 'image';

  /// Ниже основных полей: сперва имя и путь, потом уже про картинку.
  @override
  int get priority => 500;

  /// Берётся за то же, за что берётся и показ, — иначе окно обещало бы
  /// сведения о картинке там, где картинки нет.
  @override
  bool accepts(FsNode node, ContentType? type) =>
      node is FileNode &&
      node is! DirectoryNode &&
      ImageViewer.extensions.contains(extensionOf(node.name).toLowerCase());

  @override
  Future<List<NodeInfoSection>> describe(FsNode node) async {
    // Читает целиком — иначе заголовок не разобрать. Предел тот же, что у
    // показа: сведения не должны стоить дороже открытия.
    final document = await ImageDocument.read(node, settings, checkpoint: () async {});

    return [
      NodeInfoSection(
        title: 'Image',
        rows: [
          NodeInfoRow('Dimensions', '${document.width} × ${document.height}'),
          NodeInfoRow('Format', document.format),
          NodeInfoRow('Pixels', '${(document.pixels / 1000000).toStringAsFixed(1)} MP'),
        ],
      ),
    ];
  }
}
