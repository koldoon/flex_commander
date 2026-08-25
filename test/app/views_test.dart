import 'package:fc_api/fc_api.dart';
import 'package:flex_commander/bootstrap/registrations.dart';
import 'package:flex_commander/state/view_registry.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Состояния, которые могли бы принести модули.
class _Question {
  const _Question();
}

class _Password extends _Question {
  const _Password();
}

class _Other {
  const _Other();
}

/// Модуль, объявляющий вид для [_Question].
class _QuestionModule implements FcModule {
  const _QuestionModule();

  @override
  String get id => 'test.question';

  @override
  String get title => 'Question';

  @override
  void install(FcRegistry registry) {
    registry.view<_Question>((context, state) => const SizedBox.shrink());
  }
}

/// Второй модуль на тот же тип: так делать нельзя.
class _SecondQuestionModule implements FcModule {
  const _SecondQuestionModule();

  @override
  String get id => 'test.question.second';

  @override
  String get title => 'Question again';

  @override
  void install(FcRegistry registry) {
    registry.view<_Question>((context, state) => const SizedBox.shrink());
  }
}

Registrations _install(List<FcModule> modules) => Registrations(LazyServices())..installAll(modules);

void main() {
  test('вид находится по точному типу состояния', () {
    final views = ViewRegistry(_install([const _QuestionModule()]).views);

    expect(views.builderFor(_Question), isNotNull);
  });

  test('незнакомому типу вида нет — и это не заглушка, а null', () {
    final views = ViewRegistry(_install([const _QuestionModule()]).views);

    expect(views.builderFor(_Other), isNull);
  });

  test('подтип вида не наследует: заведён — значит для него и объявляют', () {
    // Иначе вид базы молча подставлялся бы там, где модуль завёл свой тип
    // ради своей же формы, — и разницы было бы не заметить.
    final views = ViewRegistry(_install([const _QuestionModule()]).views);

    expect(views.builderFor(_Password), isNull);
  });

  test('два вида на один тип — ошибка сборки, а не победа последнего', () {
    // Тихая победа последнего означала бы, что картинка зависит от порядка
    // модулей в списке, а он там стоит ради приоритета привязок клавиш.
    expect(() => _install([const _QuestionModule(), const _SecondQuestionModule()]), throwsA(isA<StateError>()));
  });
}
