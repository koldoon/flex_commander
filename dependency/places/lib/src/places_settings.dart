import 'dart:io';

import 'package:fc_api/fc_api.dart';

import 'place.dart';

/// Что полоса помнит между запусками (`docs/spec/favorites-sidebar.md`, §4).
class PlacesSettings implements Serializable {
  PlacesSettings();

  /// Показана ли полоса, пока человек её не прятал.
  ///
  /// В приложении — да. **Под `flutter test` — нет**, и это единственное
  /// место, где код смотрит, прогон ли идёт. Полоса отнимает ширину у панелей:
  /// с ней сдвинулись бы снимки окна и раскладки всех проверок, рассчитанных
  /// на две панели во всю ширину, — в корне и в каждом пакете, что собирает
  /// приложение целиком. Включать её по пакетам значило бы помнить об этом в
  /// каждом новом пакете; `FLUTTER_TEST` ставит сам `flutter test`.
  ///
  /// Проверки полосы включают её явно — для того поле и изменяемо.
  static bool visibleByDefault = !Platform.environment.containsKey('FLUTTER_TEST');

  /// Места по умолчанию — как у Finder (`docs/spec/favorites-sidebar.md`, §3).
  static List<Place> defaults() => [
    Place(address: '~'),
    Place(address: '~/Desktop'),
    Place(address: '~/Documents'),
    Place(address: '~/Downloads'),
    Place(address: '/Applications'),
    Place(address: '/'),
  ];

  /// Свой список; null — человек его ещё не складывал.
  ///
  /// Пустой список и отсутствие списка — разное: убрал все места — значит
  /// хочет пустую полосу, а не места по умолчанию при следующем запуске.
  List<Place>? _places;

  List<Place> get places => _places ??= defaults();

  set places(List<Place> value) => _places = value;

  /// Вернуть места по умолчанию.
  void restoreDefaults() => _places = defaults();

  bool? _visible;

  bool get visible => _visible ?? visibleByDefault;

  set visible(bool value) => _visible = value;

  /// Ширина, которую оттянули мышью; null — по теме.
  double? width;

  @override
  void fromMap(Map<String, dynamic> m) {
    final stored = m['places'];
    // Любой словарь, а не только `Map<String, dynamic>`: через границу
    // изолятов вложенные словари приезжают `Map<dynamic, dynamic>`, и
    // `extractList` их молча пропускал — места читались пустыми, отбрасывались,
    // и после перезапуска полоса была пуста.
    _places =
        stored is List
            ? [
              for (final item in stored)
                if (item is Map) Place()..fromMap(item.map((key, value) => MapEntry('$key', value))),
            ]
            : null;
    _places?.removeWhere((place) => place.address.trim().isEmpty);
    final visible = m['visible'];
    _visible = visible is bool ? visible : null;
    final width = m['width'];
    this.width = width is num ? width.toDouble() : null;
  }

  @override
  void toMap(Map<String, dynamic> m) {
    if (_places case final places?) {
      m['places'] = serializeList(places);
    }
    // Пишется всегда: поле в окне настроек должно найти свой ключ в файле.
    m['visible'] = visible;
    if (width case final width?) {
      m['width'] = width;
    }
  }
}
