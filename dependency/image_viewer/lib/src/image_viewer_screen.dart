import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/widgets.dart';

import 'image_document.dart';
import 'image_viewer_settings.dart';

/// Показ картинки: сама картинка и то, как её сейчас смотрят.
///
/// Соседей по каталогу держит он же: стрелки листают альбом, не выходя в
/// панель. Панель для этого не нужна — просмотрщик открывают и из палитры, и
/// из будущего поиска, где панели нет вовсе.
class ImageViewerScreen extends ChangeNotifier implements ViewerContent {
  ImageViewerScreen({
    required FileEntry entry,
    required ImageDocument document,
    required this.contentOf,
    required this.settings,
    required this.onSettingsChanged,
    this.place = ViewerPlace.fullscreen,
    List<FileEntry> siblings = const [],
  }) : _entry = entry,
       _document = document,
       _siblings = siblings;

  /// Имя в реестре просмотрщиков.
  static const String viewerId = 'image';

  /// Пределы масштаба и запомненный вид.
  final ImageViewerSettings settings;

  final void Function() onSettingsChanged;

  @override
  final ViewerPlace place;

  /// Что показано сейчас. Меняется, когда листают соседей.
  @override
  FileEntry get entry => _entry;
  FileEntry _entry;

  ImageDocument get document => _document;
  ImageDocument _document;

  /// Картинки того же каталога, в порядке панели; сюда входит и текущая.
  final List<FileEntry> _siblings;

  /// Чем прочесть соседа по списку.
  final Content Function(FileEntry entry) contentOf;

  /// Вписывать в окно или показывать точка в точку.
  bool get fitToWindow => settings.fitToWindow && _zoom == null;

  /// Заданный руками масштаб; null — вид по настройке.
  double? _zoom;

  /// Во сколько раз показывать, когда вписывать не просят.
  double get zoom => _zoom ?? 1;

  /// Смещение картинки, когда она больше окна: её возят мышью.
  Offset get offset => _offset;
  Offset _offset = Offset.zero;

  /// Наименьший и наибольший масштаб. Шаг — умножение на корень из двух: так
  /// одинаково удобно и на мелком, и на крупном.
  static const double minZoom = 0.1;
  static const double maxZoom = 8;
  static const double zoomStep = 1.4142135623730951;

  /// Есть ли куда листать. По кругу не ходим: конец списка — это конец.
  bool get hasNext => _cursor >= 0 && _cursor < _siblings.length - 1;
  bool get hasPrevious => _cursor > 0;

  /// Где мы в списке — с учётом того, куда уже идём.
  ///
  /// Не по показанному узлу: при беглом листании чтение отстаёт от нажатий, и
  /// второе нажатие целилось бы в того же соседа, что и первое.
  int get _cursor => _targetIndex ?? _indexOfCurrent;

  int get _indexOfCurrent => _siblings.indexWhere((sibling) => sibling.path == _entry.path);

  /// Куда идём, пока читается; null — пришли.
  int? _targetIndex;

  void toggleFit() {
    if (_zoom != null) {
      // Из своего масштаба возвращаемся к тому виду, который в настройке.
      _zoom = null;
    } else {
      settings.fitToWindow = !settings.fitToWindow;
      onSettingsChanged();
    }
    _offset = Offset.zero;
    notifyListeners();
  }

  void zoomBy(double factor) {
    final next = (zoom * factor).clamp(minZoom, maxZoom);
    _zoom = next;
    notifyListeners();
  }

  /// Возить картинку: то, чего стрелками не сделать — они листают.
  ///
  /// Дальше краёв не уезжает: смещение ограничено тем, насколько картинка
  /// вылезает за окно. Иначе её можно было бы утащить в пустоту и потерять из
  /// виду — а вернуть нечем, показ ведь и есть картинка.
  void moveBy(Offset delta, {required Size shown, required Size viewport}) {
    final limitX = ((shown.width - viewport.width) / 2).clamp(0.0, double.infinity);
    final limitY = ((shown.height - viewport.height) / 2).clamp(0.0, double.infinity);
    final moved = Offset(
      (_offset.dx + delta.dx).clamp(-limitX, limitX),
      (_offset.dy + delta.dy).clamp(-limitY, limitY),
    );
    if (moved == _offset) {
      return;
    }
    _offset = moved;
    notifyListeners();
  }

  /// Поколение листания: пришёл ответ не того поколения — жали дальше, и
  /// показывать догнавшее уже нельзя.
  int _generation = 0;

  /// Показать соседа: [delta] равна −1 или 1.
  ///
  /// Читает он сам и в себя же: подменять состояние в области нельзя — в
  /// быстром просмотре оно стоит внутри хозяина, и подмена унесла бы хозяина.
  Future<void> step(int delta) async {
    final index = _cursor;
    if (index < 0) {
      return;
    }
    final next = index + delta;
    if (next < 0 || next >= _siblings.length) {
      return;
    }

    _targetIndex = next;
    final generation = ++_generation;
    final sibling = _siblings[next];
    final document = await ImageDocument.read(sibling, contentOf(sibling), settings, checkpoint: () async {});
    // Распаковка до подмены: иначе на месте новой картинки видна прежняя.
    await document.warmUp();
    if (generation != _generation) {
      // Пока читали, нажали ещё раз: эта картинка уже никому не нужна, а
      // показать её значило бы вернуться назад на глазах у человека.
      document.release();
      return;
    }
    // Прежнюю отпускаем: держать распакованными все просмотренные подряд —
    // верный способ съесть память за минуту листания.
    _document.release();
    _targetIndex = null;
    _entry = sibling;
    _document = document;
    // Масштаб и смещение сбрасываются: следующая картинка другого размера, и
    // унаследованный масштаб показал бы её углом.
    _zoom = null;
    _offset = Offset.zero;
    notifyListeners();
  }

  @override
  bool get takesKeyboard => true;

  @override
  void close() => dispose();

  @override
  void dispose() {
    _document.release();
    super.dispose();
  }
}
