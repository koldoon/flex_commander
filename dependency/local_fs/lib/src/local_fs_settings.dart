import 'package:fc_api/fc_api.dart';

/// Что модуль локальной ФС помнит между запусками.
class LocalFsSettings implements Serializable {
  LocalFsSettings({this.copyProgressMinBytes = 1 << 20});

  /// С какого размера файл копируется с показом хода внутри него.
  ///
  /// Ход внутри файла стоит изолята и нативного колбэка на каждый файл: на
  /// дереве из десятков тысяч мелких файлов это дороже самой копии. Ниже порога
  /// файл копируется одним действием, а объём засчитывается по концу — как было
  /// всегда. 0 — показывать ход у любого файла.
  ///
  /// Полезное значение зависит от диска: на медленной флешке заметен и мегабайт,
  /// на NVMe не заметны и сто. Умолчание — мегабайт: ниже него файл копируется
  /// быстрее, чем окно успевает перерисоваться.
  int copyProgressMinBytes;

  @override
  void fromMap(Map<String, dynamic> m) =>
      copyProgressMinBytes = extract(copyProgressMinBytes, m['copyProgressMinBytes']);

  @override
  void toMap(Map<String, dynamic> m) => m['copyProgressMinBytes'] = copyProgressMinBytes;
}
