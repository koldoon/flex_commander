import 'package:fc_core_api/fc_core_api.dart';

import 'editor_saving.dart';
import 'editor_work.dart';

/// Редактор — ядровая половина: сохранение текста.
///
/// От целого модуля здесь одна работа, зато та, которой нужен источник: писать
/// файл — дело той стороны, где он лежит.
class TextEditorBackend implements FcBackendModule {
  const TextEditorBackend();

  @override
  String get id => 'fc.editor';

  @override
  String get title => 'Text editor';

  @override
  void installBackend(BackendRegistry registry) {
    registry.operation(EditorWork.kind, (services) => EditorSaving.operation());
  }
}
