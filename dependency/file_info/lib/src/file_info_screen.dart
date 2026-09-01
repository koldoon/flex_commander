import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:flutter/widgets.dart';

/// Что показывает один провайдер: раздел, ожидание или ошибка.
///
/// Три состояния, а не два, и различать их обязательно: «идёт» и «не смог» —
/// разные новости, а «нечего сказать» вообще не новость и в окне не место.
class NodeInfoPart {
  NodeInfoPart({required this.id, required this.title});

  /// Имя провайдера — чтобы раздел не потерялся среди одинаковых заголовков.
  final String id;

  /// Заголовок на время ожидания: у провайдера он один, а разделов он может
  /// дать и несколько.
  final String title;

  /// Что рассказал; пусто, пока идёт.
  List<NodeInfoSection> sections = const [];

  /// Ошибка того, кто **взялся** и не смог. Это сведение о файле, а не о
  /// приложении: значит, файл битый или сведения в нём противоречивы.
  String? error;

  bool loading = true;
}

/// Сведения об узле: то, что рассказали провайдеры.
///
/// Одно состояние на оба места — окно и показ. Разное у них только рама, а
/// разделы одни и те же: два показа одного и того же однажды разойдутся.
class FileInfoScreen extends ChangeNotifier implements ViewerContent {
  FileInfoScreen({required this.app, required List<FsNode> nodes, this.place = ViewerPlace.fullscreen})
    : _nodes = nodes {
    _ask();
  }

  /// Имя в реестре просмотрщиков.
  static const String viewerId = 'info';

  final Application app;

  final List<FsNode> _nodes;

  @override
  final ViewerPlace place;

  /// Об одном узле — сведения; о нескольких — сводка (§5 спеки).
  bool get isSummary => _nodes.length > 1;

  @override
  FsNode get node => _nodes.first;

  /// Разделы по провайдерам, сверху вниз.
  List<NodeInfoPart> get parts => List.unmodifiable(_parts);
  final List<NodeInfoPart> _parts = [];

  /// Сводка по помеченному: считается сразу, обхода дерева не требует.
  List<NodeInfoRow> get summary => [
    NodeInfoRow('Items', '${_nodes.length}'),
    NodeInfoRow('Directories', '${_nodes.whereType<DirectoryNode>().length}'),
    NodeInfoRow(
      'Size',
      formatBytesExact(_nodes.where((node) => node.size > 0).fold(0, (sum, node) => sum + node.size)),
    ),
  ];

  /// Размер каталога: null — ещё не считали.
  int? get directorySize => _directorySize;
  int? _directorySize;

  bool get counting => _counting;
  bool _counting = false;

  /// Есть ли что считать: у каталога размер сам не берётся.
  bool get canCount => !isSummary && node is DirectoryNode;

  /// Посчитать размер каталога — тем же обходом, что и `Alt-Shift-Enter`.
  ///
  /// По кнопке, а не при открытии: сведения о `/` не должны означать обход
  /// диска.
  Future<void> count() async {
    final directory = node;
    if (_counting || directory is! DirectoryNode) {
      return;
    }
    _counting = true;
    notifyListeners();

    var total = 0;
    try {
      await directory.provider.countEntries(directory, (size) {
        if (size > 0) {
          total += size;
        }
      });
      _directorySize = total;
    } on Object {
      // Не сосчиталось — покажем, сколько успели: это честнее пустоты.
      _directorySize = total;
    } finally {
      _counting = false;
      notifyListeners();
    }
  }

  /// Спрашивает всех, кто берётся, — и каждого по отдельности.
  ///
  /// Порознь, а не общим `Future.wait`: окно не должно ждать самого
  /// медленного, а раздел появляется, как только его рассказали.
  void _ask() {
    if (isSummary) {
      // У пятнадцати файлов «метод сжатия» — не сведения, а каша.
      return;
    }

    for (final provider in app.nodeInfoProviders) {
      // Тип по содержимому появится в Б6; пока его нет, провайдер решает по
      // имени — как и просмотрщики.
      if (!provider.accepts(node, null)) {
        // Не взялся — раздела нет вовсе: ни пустого заголовка, ни ошибки.
        continue;
      }

      final part = NodeInfoPart(id: provider.id, title: provider.id);
      _parts.add(part);
      unawaited(_fill(part, provider));
    }
  }

  Future<void> _fill(NodeInfoPart part, NodeInfoProvider provider) async {
    try {
      final sections = await provider.describe(node);
      part.sections = sections;
      part.error = null;
    } on Object catch (error) {
      // Взялся и не смог. Это и есть сведение: провайдер объявил, что читает
      // такой формат, получил его и не разобрал.
      part.error = error is FsError ? error.message : '$error';
    } finally {
      part.loading = false;
      // Раздел, которому нечего сказать, уходит совсем: пустой заголовок —
      // обещание, которого не сдержали.
      if (part.error == null && part.sections.isEmpty) {
        _parts.remove(part);
      }
      notifyListeners();
    }
  }

  @override
  bool get takesKeyboard => false;

  @override
  void close() => dispose();
}
