import 'package:fc_api/fc_api.dart';
import 'package:fc_key_presets/fc_key_presets.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// Сами наборы: что в них написано (`docs/spec/key-presets.md`).
///
/// Что записи попадают в настоящие привязки — проверяется в собранном
/// приложении (`test/app/key_presets_test.dart`): здесь модулей нет.
void main() {
  test('модуль объявляет три набора', () {
    final declared = <String>[];
    const KeyPresets().installFrontend(_Collector(declared));

    expect(declared, ['mc', 'far', 'Finder']);
  });

  test('в наборе нет пустых имён и клавиш без дела', () {
    final presets = <String, List<String>>{};
    const KeyPresets().installFrontend(_Collector([], into: presets));

    for (final entry in presets.entries) {
      expect(entry.value, isNotEmpty, reason: 'набор «${entry.key}» пуст');
      for (final binding in entry.value) {
        expect(binding, isNotEmpty, reason: 'в наборе «${entry.key}» запись без имени привязки');
      }
    }
  });
}

/// Ловит объявленное, ничего больше не делая.
class _Collector implements FrontendRegistry {
  const _Collector(this.names, {this.into});

  final List<String> names;
  final Map<String, List<String>>? into;

  @override
  void preset(Preset preset) {
    names.add(preset.name);
    into?[preset.name] = [for (final override in preset.keys) override.binding];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
