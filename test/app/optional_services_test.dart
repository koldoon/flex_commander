import 'package:dicom/dicom.dart';
import 'package:flex_commander/bootstrap/registrations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Необязательная служба, которой никто не объявил.
///
/// Так модули спрашивают о том, без чего умеют обойтись: нет модуля типов —
/// правила по содержимому не совпадают; нет миниатюр — значок берётся
/// следующим правилом. Ответ на такой вопрос — пустой список, а не падение.
abstract interface class _Nobody {}

class _Somebody {}

void main() {
  test('о необъявленной службе спрашивают без последствий', () {
    final services = LazyServices();
    final container = DI();
    container.bind<_Somebody>(to: (c) => _Somebody());
    services.bindTo(container);

    expect(services.resolveAll<_Nobody>(), isEmpty, reason: '«сколько есть» — это ноль, а не ошибка');
    expect(services.resolveAll<_Somebody>(), hasLength(1));

    // И главное: вопрос о несуществующем не портит контейнер. Отказ, вылетевший
    // из фабрики, сбивает ему разбор зависимостей — падает уже следующий
    // вопрос, и падает не там, где причина.
    expect(services.resolveAll<_Nobody>(), isEmpty);
    expect(services.resolve<_Somebody>(), isA<_Somebody>());
  });
}
