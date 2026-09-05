import 'package:fc_api/fc_api.dart';

/// Что определение типов помнит между запусками.
class ContentTypesSettings implements Serializable {
  ContentTypesSettings({this.concurrency = defaultConcurrency});

  /// Сколько файлов читается разом.
  ///
  /// Четыре, а не «сколько получится»: по `ssh` каждая проверка — запрос к
  /// серверу, и десять тысяч строк в каталоге не повод устроить десять тысяч
  /// запросов.
  static const int defaultConcurrency = 4;

  int concurrency;

  @override
  void fromMap(Map<String, dynamic> m) {
    concurrency = extract(concurrency, m['concurrency']);
  }

  @override
  void toMap(Map<String, dynamic> m) {
    m['concurrency'] = concurrency;
  }
}
