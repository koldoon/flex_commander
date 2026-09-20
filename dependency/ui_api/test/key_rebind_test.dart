import 'package:fc_api/fc_api.dart';
import 'package:flutter/foundation.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// Переназначение клавиш (`docs/spec/key-bindings.md`, §5).
///
/// Проверяется реестр, а не окно: подмена комбинации у объявленной привязки —
/// и есть всё переназначение.
void main() {
  CommandRegistry registryWith(List<KeyBinding> bindings) => CommandRegistry(const [], bindings);

  List<String> keysOf(CommandRegistry registry, String commandId) => [
    for (final binding in registry.bindingsOf(commandId)) binding.keys.toString(),
  ];

  test('переназначение подменяет клавишу объявленной привязки', () {
    final registry = registryWith([KeyBinding('F5', 'file.copy'), KeyBinding('F6', 'file.move')]);

    registry.rebind([KeyOverride(command: 'file.copy', was: 'F5', now: 'Ctrl-C')]);

    expect(keysOf(registry, 'file.copy'), ['Ctrl-C']);
    expect(keysOf(registry, 'file.move'), ['F6'], reason: 'чужую привязку трогать не за что');
  });

  test('место, значения и условие по имени остаются прежними', () {
    final binding = KeyBinding.inState<_Screen>('F5', 'text.format', parameters: const {'mode': 'raw'});
    final registry = registryWith([binding]);

    registry.rebind([KeyOverride(command: 'text.format', was: 'F5', now: 'F8')]);

    final after = registry.bindingsOf('text.format').single;
    expect(after.keys.toString(), 'F8');
    expect(after.parameters, {'mode': 'raw'}, reason: 'человек менял клавишу, а не смысл');
    expect(after.inContent, same(binding.inContent), reason: 'место привязки — дело модуля');
  });

  test('снятое переназначение возвращает умолчание', () {
    final registry = registryWith([KeyBinding('F5', 'file.copy')]);
    registry.rebind([KeyOverride(command: 'file.copy', was: 'F5', now: 'Ctrl-C')]);

    registry.rebind([]);

    expect(keysOf(registry, 'file.copy'), ['F5']);
  });

  test('пустая клавиша оставляет привязку без нажатия', () {
    final registry = registryWith([KeyBinding('F5', 'file.copy')]);

    registry.rebind([KeyOverride(command: 'file.copy', was: 'F5', now: '')]);

    expect(registry.bindingsOf('file.copy').single.keys, KeyCombination.none);
    expect(registry.commandFor(KeyCombination.parse('F5')), isNull, reason: 'клавиша снята, а отзывается');
  });

  test('переназначение к чужому умолчанию не липнет', () {
    // Сменилось умолчание в новом выпуске — переназначение отпадает, и человек
    // видит новое умолчание (§4).
    final registry = registryWith([KeyBinding('Shift-F5', 'file.copy')]);

    registry.rebind([KeyOverride(command: 'file.copy', was: 'F5', now: 'Ctrl-C')]);

    expect(keysOf(registry, 'file.copy'), ['Shift-F5']);
  });

  test('порядок привязок не меняется', () {
    // Порядком решается, кому достанется клавиша, когда выполнимы обе.
    final registry = registryWith([KeyBinding('F3', 'viewer.open'), KeyBinding('F3', 'shell.open')]);

    registry.rebind([KeyOverride(command: 'shell.open', was: 'F3', now: 'F4')]);

    expect(registry.bindings.map((binding) => binding.commandId).toList(), ['viewer.open', 'shell.open']);
  });

  group('столкновение — это спор за одно нажатие', () {
    test('одна клавиша в разных местах не спорит', () {
      // `F5` в панели копирует, в просмотрщике форматирует — и это задумано
      // (`docs/spec/key-bindings.md`, §3).
      final panel = KeyBinding('F5', 'file.copy');
      final screen = KeyBinding.inState<_Screen>('F5', 'text.format');

      expect(panel.conflictsWith(screen), isFalse);
    });

    test('в одном месте — спорит', () {
      expect(KeyBinding('F5', 'file.copy').conflictsWith(KeyBinding('F5', 'file.move')), isTrue);
    });

    test('разные клавиши не спорят никогда', () {
      expect(KeyBinding('F5', 'file.copy').conflictsWith(KeyBinding('F6', 'file.move')), isFalse);
    });

    test('условие по имени разводит привязки', () {
      // `Enter` на архиве и `Enter` на обычном файле — разные привязки.
      final archive = KeyBinding('Enter', 'file.open', nameMatch: RegExp(r'\.zip$'));
      final plain = KeyBinding('Enter', 'file.open');

      expect(archive.conflictsWith(plain), isFalse);
    });
  });

  test('объявленное помнится и после переназначения', () {
    final registry = registryWith([KeyBinding('F5', 'file.copy')]);

    registry.rebind([KeyOverride(command: 'file.copy', was: 'F5', now: 'Ctrl-C')]);

    expect(registry.declaredBindings.single.keys.toString(), 'F5');
  });
}

/// Экран-подставка: нужен только как «место» привязки.
class _Screen extends ChangeNotifier implements ViewportState {
  @override
  bool get takesKeyboard => false;

  @override
  void close() {}
}
