import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flex_commander/bootstrap/frontend_registrations.dart';
import 'package:flex_commander/bootstrap/registrations.dart';
import 'package:flex_commander/state/view_registry.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Состояния, которые могли бы принести модули.
class _Question {
  const _Question();
}

abstract interface class _Secret {}

class _Password extends _Question implements _Secret {
  const _Password();
}

class _Other {
  const _Other();
}

/// Модуль, объявляющий вид для [_Question].
class _QuestionModule implements FcFrontendModule {
  const _QuestionModule();

  @override
  String get id => 'test.question';

  @override
  String get title => 'Question';

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.view<_Question>((context, state) => const SizedBox.shrink());
  }
}

/// Модуль с видом ровно на [_Password].
class _PasswordModule implements FcFrontendModule {
  const _PasswordModule();

  @override
  String get id => 'test.password';

  @override
  String get title => 'Password';

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.view<_Password>((context, state) => const SizedBox.shrink());
  }
}

/// Модуль с видом на второй интерфейс того же состояния: выбирать между ним и
/// видом на базу — значит выбирать по порядку модулей.
class _MarkerModule implements FcFrontendModule {
  const _MarkerModule();

  @override
  String get id => 'test.marker';

  @override
  String get title => 'Marker';

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.view<_Secret>((context, state) => const SizedBox.shrink());
  }
}

/// Второй модуль на тот же тип: так делать нельзя.
class _SecondQuestionModule implements FcFrontendModule {
  const _SecondQuestionModule();

  @override
  String get id => 'test.question.second';

  @override
  String get title => 'Question again';

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.view<_Question>((context, state) => const SizedBox.shrink());
  }
}

FrontendRegistrations _install(List<FcFrontendModule> modules) =>
    FrontendRegistrations(LazyServices())..installAll(modules);

void main() {
  test('вид находится по точному типу состояния', () {
    final views = ViewRegistry(_install([const _QuestionModule()]).views);

    expect(views.builderFor(const _Question()), isNotNull);
  });

  test('незнакомому состоянию вида нет — и это не заглушка, а null', () {
    final views = ViewRegistry(_install([const _QuestionModule()]).views);

    expect(views.builderFor(const _Other()), isNull);
  });

  test('вид на интерфейс подходит его реализации', () {
    // Иначе объявить вид на `Panel` было бы невозможно: придёт
    // `Panel`, и по типу они не совпадут никогда.
    final views = ViewRegistry(_install([const _QuestionModule()]).views);

    expect(views.builderFor(const _Password()), isNotNull);
  });

  test('точный тип идёт вперёд подходящего', () {
    final views = ViewRegistry(_install([const _QuestionModule(), const _PasswordModule()]).views);

    expect(views.builderFor(const _Password()), same(views.builderFor(const _Password())));
    expect(
      views.builderFor(const _Password()),
      isNot(same(views.builderFor(const _Question()))),
      reason: 'вид, объявленный ровно на этот тип, ближе к делу, чем вид на его базу',
    );
  });

  test('два вида на один тип — ошибка сборки, а не победа последнего', () {
    // Тихая победа последнего означала бы, что картинка зависит от порядка
    // модулей в списке, а он там стоит ради приоритета привязок клавиш.
    expect(() => _install([const _QuestionModule(), const _SecondQuestionModule()]), throwsA(isA<StateError>()));
  });

  test('два подходящих вида и ни одного точного — тоже ошибка', () {
    final views = ViewRegistry(_install([const _QuestionModule(), const _MarkerModule()]).views);

    expect(() => views.builderFor(const _Password()), throwsA(isA<StateError>()));
  });
}
