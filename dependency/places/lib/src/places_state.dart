import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/foundation.dart';

import 'place.dart';
import 'places_settings.dart';

/// Боковая полоса избранного — содержимое области `sidebar`.
///
/// Держит места (в настройках модуля), курсор полосы, начатое переименование и
/// места, куда последняя попытка не дошла. Переходит сама, напрямую через
/// `Session.openPath`: команда `panel.openPath` всегда делает свою панель
/// активной, и `Cmd`-щелчок — переход в соседней — с ней не сложился бы
/// (`docs/spec/favorites-sidebar.md`, §5).
class PlacesState extends ChangeNotifier implements ViewportState {
  PlacesState({required this.app, required PlacesSettings Function() settings, required void Function() save})
    : _settings = settings,
      _save = save;

  final Application app;
  final PlacesSettings Function() _settings;
  final void Function() _save;

  List<Place> get places => _settings().places;

  /// Курсор полосы. Виден, только пока у полосы ввод.
  int get cursor => places.isEmpty ? 0 : _cursor.clamp(0, places.length - 1);
  int _cursor = 0;

  /// Место, имя которого правят; null — не правят.
  int? get renaming => _renaming;
  int? _renaming;

  /// Куда последняя попытка не дошла — по адресу.
  ///
  /// Только в памяти: «недоступно» значит «в прошлый раз не вышло», а не
  /// «нет сейчас», и тащить это через перезапуск незачем (§5.3).
  final Set<String> _unreachable = {};

  bool isUnreachable(Place place) => _unreachable.contains(place.address);

  /// Ширина полосы — оттянутая мышью или по теме.
  double? get width => _settings().width;

  /// Пока правят имя, системный фокус нужен полю ввода.
  @override
  bool get takesKeyboard => _renaming != null;

  /// Держать нечего: места — в настройках, а соединения — у панелей.
  @override
  void close() {}

  /// Имя места на полосе: своё или по умолчанию, переведённое у знакомых мест.
  String nameOf(Place place) {
    if (place.name case final name?) {
      return name;
    }
    final fallback = PlaceAddress.defaultName(place.address);
    return PlaceAddress.isTranslatedName(place.address) ? app.strings.tr(fallback, context: 'place') : fallback;
  }

  /// Домашний каталог этой машины — от той панели, что смотрит в локальную
  /// файловую систему. Нужен, чтобы `/Users/me/Downloads` и `~/Downloads`
  /// оказались одним местом.
  String get _home {
    for (final panel in [app.activePanel, app.passivePanel]) {
      if (panel.source.scheme == 'fs' && panel.source.homePath.isNotEmpty) {
        return panel.source.homePath;
      }
    }
    return '';
  }

  String _key(String address) => PlaceAddress.normalize(address, home: _home);

  /// Путь места на этой машине; null — у места его нет.
  ///
  /// Нужен значку системы: она рисует его по настоящему пути. У сервера и у
  /// места в архиве пути этой машины нет, у `~` без известного домашнего
  /// каталога — тоже.
  String? localPathOf(Place place) {
    switch (PlaceAddress.kindOf(place.address)) {
      case PlaceKind.server || PlaceKind.archive:
        return null;
      default:
        break;
    }
    final address = PlaceAddress.normalize(place.address);
    if (address.startsWith('/')) {
      return address;
    }
    final home = _home;
    if (home.isEmpty) {
      return null;
    }
    if (address == '~') {
      return home;
    }
    return address.startsWith('~/') ? '$home${address.substring(1)}' : null;
  }

  /// Индекс места с таким адресом; -1 — такого нет.
  int indexOf(String address) {
    final key = _key(address);
    return places.indexWhere((place) => _key(place.address) == key);
  }

  void moveCursor(int index) {
    if (places.isEmpty) {
      return;
    }
    final next = index.clamp(0, places.length - 1);
    if (next == _cursor) {
      return;
    }
    _cursor = next;
    notifyListeners();
  }

  /// Перейти к месту: в активную панель или в соседнюю ([other]).
  ///
  /// Соседняя активной не становится — так и задумано. Занятая панель перехода
  /// не принимает, как не принимает и нажатий.
  Future<bool> open(int index, {bool other = false}) async {
    if (index < 0 || index >= places.length) {
      return false;
    }
    final place = places[index];
    final panel = other ? app.passivePanel : app.activePanel;
    if (panel.busy) {
      return false;
    }
    _cursor = index;
    final ok = await panel.openPath(place.address);
    if (ok) {
      _unreachable.remove(place.address);
      // Пришли в активную — ввод ей: дальше работают там. Соседняя ввода не
      // получает, и полоса с фокусом остаётся при нём. Не дошли — тоже
      // остаётся: следующее место выбирают отсюда же.
      if (!other && app.view.activeArea == ViewportPosition.sidebar) {
        app.view.setFocus(app.view.sourceArea);
      }
    } else {
      _unreachable.add(place.address);
      if (panel.error case final error?) {
        app.toasts.fail(app.strings.describe(error));
      } else {
        app.toasts.fail(app.strings.tr('Cannot open {address}', args: {'address': place.address}));
      }
    }
    notifyListeners();
    return ok;
  }

  /// Добавить место; [at] — куда встать, null — в конец.
  ///
  /// Повтор не заводится: курсор встаёт на имеющееся место, и об этом говорит
  /// тост. Возвращает индекс места на полосе.
  int add(String address, {int? at}) {
    final value = _key(address);
    if (value.isEmpty) {
      return -1;
    }
    final existing = indexOf(value);
    if (existing >= 0) {
      _cursor = existing;
      app.toasts.show(app.strings.tr('Already in sidebar'));
      notifyListeners();
      return existing;
    }
    final list = places;
    final index = (at ?? list.length).clamp(0, list.length);
    list.insert(index, Place(address: value));
    _settings().places = list;
    _cursor = index;
    _save();
    notifyListeners();
    return index;
  }

  /// Убрать место. Без вопроса, как в Finder: вернуть — тем же броском, а весь
  /// список — кнопкой «Restore defaults» в настройках.
  void remove(int index) {
    final list = places;
    if (index < 0 || index >= list.length) {
      return;
    }
    list.removeAt(index);
    _settings().places = list;
    if (_cursor >= list.length) {
      _cursor = list.isEmpty ? 0 : list.length - 1;
    }
    _save();
    notifyListeners();
  }

  /// Переставить место: [to] — позиция **между** строками до переноса, как
  /// её показывает линия вставки.
  void move(int from, int to) {
    final list = places;
    if (from < 0 || from >= list.length) {
      return;
    }
    var target = to.clamp(0, list.length);
    if (target == from || target == from + 1) {
      return;
    }
    final place = list.removeAt(from);
    if (target > from) {
      target--;
    }
    list.insert(target, place);
    _settings().places = list;
    _cursor = target;
    _save();
    notifyListeners();
  }

  void startRename(int index) {
    if (index < 0 || index >= places.length) {
      return;
    }
    _cursor = index;
    _renaming = index;
    notifyListeners();
  }

  /// Принять имя. Пустое — вернуть имя по умолчанию.
  void commitRename(String value) {
    final index = _renaming;
    if (index == null) {
      return;
    }
    _renaming = null;
    if (index < places.length) {
      final name = value.trim();
      final place = places[index];
      place.name = name.isEmpty || name == PlaceAddress.defaultName(place.address) ? null : name;
      _settings().places = places;
      _save();
    }
    notifyListeners();
  }

  void cancelRename() {
    if (_renaming == null) {
      return;
    }
    _renaming = null;
    notifyListeners();
  }

  /// Ширина на ходу — без записи: пишется по отпусканию ([saveWidth]).
  void setWidth(double value) {
    if (_settings().width == value) {
      return;
    }
    _settings().width = value;
    notifyListeners();
  }

  void saveWidth() => _save();

  /// Вернуть места по умолчанию — кнопкой в настройках.
  void restoreDefaults() {
    _settings().restoreDefaults();
    _cursor = 0;
    _renaming = null;
    _unreachable.clear();
    _save();
    notifyListeners();
  }
}
