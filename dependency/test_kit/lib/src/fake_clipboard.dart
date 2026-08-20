import 'package:fc_api/fc_api.dart';

/// Буфер обмена в памяти.
///
/// Без него прогон трогал бы настоящий буфер машины: человек за ней в это
/// время что-то копировал, и тест бы это молча стёр.
class FakeClipboard implements ClipboardService {
  String? text;

  /// Что клали, по порядку, — по ним видно и сколько раз копировали.
  final List<String> written = [];

  @override
  Future<void> writeText(String value) async {
    text = value;
    written.add(value);
  }

  @override
  Future<String?> readText() async => text;
}
