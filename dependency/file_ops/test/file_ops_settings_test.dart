import 'package:fc_api/fc_api.dart';
import 'package:fc_file_ops/fc_file_ops.dart';
import 'package:flutter_test/flutter_test.dart';

/// Что окно переименования помнит между запусками
/// (`docs/spec/multi-rename.md`, §12).
void main() {
  test('набранное и наборы переживают запись на диск', () {
    final settings =
        FileOpsSettings()
          ..lastRename = const RenameSpec(nameMask: 'Отпуск_[C]', nameCase: RenameCase.upper)
          ..saveRenamePreset('снимки', const RenameSpec(nameMask: 'IMG_[C]', extensionMask: 'jpg'));

    final stored = <String, dynamic>{};
    settings.toMap(stored);
    final read = FileOpsSettings()..fromMap(stored);

    expect(read.lastRename.nameMask, 'Отпуск_[C]');
    expect(read.lastRename.nameCase, RenameCase.upper);
    expect(read.renamePresetNames, ['снимки']);
    expect(read.renamePreset('снимки')?.extensionMask, 'jpg');
  });

  test('одноимённый набор переписывается, а не ложится вторым', () {
    final settings =
        FileOpsSettings()
          ..saveRenamePreset('снимки', const RenameSpec(nameMask: 'IMG_[C]'))
          ..saveRenamePreset('снимки', const RenameSpec(nameMask: 'Отпуск_[C]'));

    expect(settings.renamePresetNames, ['снимки']);
    expect(settings.renamePreset('снимки')?.nameMask, 'Отпуск_[C]');
  });

  test('безымянный набор не записывается', () {
    final settings = FileOpsSettings()..saveRenamePreset('   ', const RenameSpec());

    expect(settings.renamePresetNames, isEmpty);
  });

  test('удалённого набора нет', () {
    final settings =
        FileOpsSettings()
          ..saveRenamePreset('снимки', const RenameSpec())
          ..removeRenamePreset('снимки');

    expect(settings.renamePresetNames, isEmpty);
    expect(settings.renamePreset('снимки'), isNull);
  });

  test('чужого мусора в файле хватает, чтобы вернуться к умолчанию', () {
    final read = FileOpsSettings()..fromMap({'lastRename': 'не карта', 'renamePresets': 42});

    expect(read.lastRename.nameMask, '[N]');
    expect(read.renamePresetNames, isEmpty);
  });
}
