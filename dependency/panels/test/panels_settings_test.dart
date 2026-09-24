import 'package:fc_panels/fc_panels.dart';
import 'package:flutter_test/flutter_test.dart';

/// Настройка «чем жертвовать в длинном имени» (`docs/spec/name-trim.md`).
void main() {
  test('выбранное переживает запись на диск', () {
    final settings = PanelsSettings()..nameTrim = PanelsSettings.trimMiddle;

    final stored = <String, dynamic>{};
    settings.toMap(stored);
    final read = PanelsSettings()..fromMap(stored);

    expect(read.nameTrim, PanelsSettings.trimMiddle);
    expect(read.trimsNameInMiddle, isTrue);
  });

  test('умолчание — хвост: у того, кто настройку не трогал, не меняется ничего', () {
    expect(PanelsSettings().nameTrim, PanelsSettings.trimEnd);
    expect(PanelsSettings().trimsNameInMiddle, isFalse);
  });

  test('незнакомое слово в файле читается как хвост', () {
    // Чужая настройка или правка руками: показываем как было, а не гадаем.
    final read = PanelsSettings()..fromMap({'nameTrim': 'по словам'});

    expect(read.nameTrim, PanelsSettings.trimEnd);
  });

  test('правка оповещает: иначе панель узнает о ней когда-нибудь потом', () {
    var heard = 0;
    final settings = PanelsSettings()..addListener(() => heard++);

    settings.nameTrim = PanelsSettings.trimMiddle;
    expect(heard, 1);

    // То же значение — не правка: лишняя перерисовка панели никому не нужна.
    settings.nameTrim = PanelsSettings.trimMiddle;
    expect(heard, 1);

    settings.fromMap({'nameTrim': PanelsSettings.trimEnd});
    expect(heard, 2, reason: 'настройки перечитали целиком — виды обязаны это увидеть');
  });
}
