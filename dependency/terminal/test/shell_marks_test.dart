import 'package:fc_terminal/frontend.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

/// Уговор с оболочкой и разбор метки.
///
/// Метка возвращает то, что теряется в постоянной сессии: конец команды, код
/// возврата и каталог. Без неё все правила показа экрана рассыпаются —
/// `docs/spec/single-shell-session.md`, §3.
void main() {
  test('межстрочная у нас и у xterm одна и та же', () {
    // Приложение подстраивается под терминал, а не наоборот: у него строка
    // обязана попадать в клетку, у остальных — нет. Разойдись эти двое, и одно
    // и то же приглашение в терминале и в командной строке встанет на пару
    // пикселей врозь.
    expect(FcTheme.terminalLineHeight, const TerminalStyle().height);
  });

  group('разбор метки', () {
    final agreement = ShellAgreement(nonce: 'abcd');

    test('код возврата и каталог доходят как есть', () {
      final mark = agreement.parse('777', ['fc', 'abcd', 'p', '0', '/home/koldoon']);
      expect(mark?.kind, ShellMarkKind.prompt);
      expect(mark?.exitCode, 0);
      expect(mark?.directory, '/home/koldoon');
    });

    test('метка о запуске приходит своим видом', () {
      // Без неё вывод команды не отличить от её отражения: оболочка отражает
      // набранное, и «молча и успешно» не бывает никогда.
      final mark = agreement.parse('777', ['fc', 'abcd', 'r']);
      expect(mark?.kind, ShellMarkKind.running);
    });

    test('чужая метка не наша', () {
      // Двоичный файл в `cat` печатает что угодно, и принять его вывод за
      // метку нельзя.
      expect(agreement.parse('777', ['fc', 'ffff', 'p', '0', '/tmp']), isNull);
      expect(agreement.parse('133', ['fc', 'abcd', 'p', '0', '/tmp']), isNull);
      expect(agreement.parse('777', ['other', 'abcd', 'p', '0', '/tmp']), isNull);
      expect(agreement.parse('777', ['fc', 'abcd', 'x']), isNull, reason: 'вид метки незнакомый');
    });

    test('точка с запятой в имени каталога не ломает разбор', () {
      // Разбор OSC режет по ней наравне с настоящими разделителями — потому
      // каталог и стоит последним, а хвост собирается обратно.
      final mark = agreement.parse('777', ['fc', 'abcd', 'p', '1', '/tmp/a', 'b']);
      expect(mark?.directory, '/tmp/a;b');
      expect(mark?.exitCode, 1);
    });

    test('без кода возврата метки нет', () {
      expect(agreement.parse('777', ['fc', 'abcd', 'p', 'нет', '/tmp']), isNull);
      expect(agreement.parse('777', ['fc', 'abcd', 'p']), isNull);
    });

    test('у каждой сессии своё число', () {
      expect(ShellAgreement().nonce, isNot(ShellAgreement().nonce));
    });
  });

  group('строка уговора', () {
    final agreement = ShellAgreement(nonce: 'abcd');

    test('fish узнаётся по имени и получает своё', () {
      final setup = agreement.setupFor('/opt/homebrew/bin/fish');
      expect(setup, contains('--on-event fish_prompt'));
      expect(setup, contains('--on-event fish_preexec'), reason: 'и метка о запуске');
      expect(setup, isNot(contains('PROMPT_COMMAND')));
    });

    test('остальным — общая строка, которая разбирается сама', () {
      // Снаружи узнать оболочку нечем: на той стороне `ssh` мы про неё не
      // знаем ничего.
      for (final shell in [null, '/bin/zsh', '/bin/bash', '/bin/sh']) {
        final setup = agreement.setupFor(shell);
        expect(setup, contains(r'$ZSH_VERSION'), reason: 'ветка zsh');
        expect(setup, contains(r'$BASH_VERSION'), reason: 'ветка bash');
        expect(setup, contains('preexec_functions='), reason: 'запуск в zsh');
        expect(setup, contains(r'PS0='), reason: 'запуск в bash');
      }
    });

    test('массив zsh спрятан в eval', () {
      // `precmd_functions=(…)` для `dash` — ошибка разбора, а разбирает он всю
      // строку целиком, ещё до того как выполнить хоть что-то из неё.
      final setup = agreement.setupFor('/bin/bash');
      final array = setup.indexOf('precmd_functions=(');
      expect(array, greaterThan(0));
      expect(setup.lastIndexOf("eval '", array), greaterThan(0));
    });

    test('строка одна: её отправляют в оболочку целиком', () {
      expect(agreement.setupFor(null), isNot(contains('\n')));
      expect(agreement.setupFor('/bin/fish'), isNot(contains('\n')));
    });

    test('в метку зашито число этой сессии', () {
      expect(agreement.setupFor(null), contains('777;fc;abcd;p;'));
      expect(agreement.setupFor(null), contains('777;fc;abcd;r'));
    });
  });
}
