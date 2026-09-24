import 'package:fc_api/fc_api.dart';

import 'rename_plan.dart';

/// Что файловые операции помнят между запусками.
///
/// Пока это только групповое переименование: чем переименовывали в прошлый раз
/// и именованные наборы правил (`docs/spec/multi-rename.md`, §12).
class FileOpsSettings implements Serializable {
  FileOpsSettings();

  /// Чем переименовывали в прошлый раз.
  ///
  /// Окно открывается там, где его закрыли: маска набирается долго, а нужна
  /// она обычно дважды подряд — сперва на пробной пачке, потом на настоящей.
  RenameSpec lastRename = const RenameSpec();

  /// Наборы правил, в порядке добавления.
  ///
  /// Списком, а не словарём: порядок в нём виден человеку, а словарь на диске
  /// его не хранит.
  List<RenamePreset> renamePresets = <RenamePreset>[];

  /// Имена наборов — ими список и рисуется.
  List<String> get renamePresetNames => [for (final preset in renamePresets) preset.name];

  RenameSpec? renamePreset(String name) {
    for (final preset in renamePresets) {
      if (preset.name == name) {
        return preset.spec;
      }
    }
    return null;
  }

  /// Записать набор под именем: одноимённый **переписывается**, а спрашивает
  /// ли кто-то согласия — дело того, кто зовёт.
  void saveRenamePreset(String name, RenameSpec spec) {
    final title = name.trim();
    if (title.isEmpty) {
      return;
    }
    final at = renamePresets.indexWhere((preset) => preset.name == title);
    if (at < 0) {
      renamePresets.add(RenamePreset(name: title, spec: spec));
    } else {
      renamePresets[at] = RenamePreset(name: title, spec: spec);
    }
  }

  void removeRenamePreset(String name) => renamePresets.removeWhere((preset) => preset.name == name);

  @override
  void fromMap(Map<String, dynamic> m) {
    final last = m['lastRename'];
    lastRename = last is Map ? RenameSpec.fromMap(Map<String, Object?>.from(last)) : const RenameSpec();
    final stored = m['renamePresets'];
    renamePresets = [
      if (stored is List)
        for (final item in stored)
          if (item is Map && item['name'] is String && item['spec'] is Map)
            RenamePreset(
              name: item['name'] as String,
              spec: RenameSpec.fromMap(Map<String, Object?>.from(item['spec'] as Map)),
            ),
    ];
  }

  @override
  void toMap(Map<String, dynamic> m) {
    m['lastRename'] = lastRename.toMap();
    m['renamePresets'] = [
      for (final preset in renamePresets) {'name': preset.name, 'spec': preset.spec.toMap()},
    ];
  }
}

/// Набор правил переименования под своим именем.
class RenamePreset {
  const RenamePreset({required this.name, required this.spec});

  final String name;
  final RenameSpec spec;
}
