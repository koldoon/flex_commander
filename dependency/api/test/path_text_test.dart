import 'package:fc_api/fc_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// Путь так, как его показывают и запоминают.
void main() {
  test('хвостовой разделитель убирается', () {
    expect(pathWithoutTrailingSlash('/home/docs/'), '/home/docs');
    expect(pathWithoutTrailingSlash('ssh://koldoon@shark/mnt/'), 'ssh://koldoon@shark/mnt');
  });

  test('путь без него остаётся собой', () {
    expect(pathWithoutTrailingSlash('/home/docs'), '/home/docs');
    expect(pathWithoutTrailingSlash(''), '');
  });

  test('корень — это и есть разделитель', () {
    expect(pathWithoutTrailingSlash('/'), '/');
  });

  test('голую схему обрезать нечем: её уже не открыть', () {
    expect(pathWithoutTrailingSlash('ssh://'), 'ssh://');
  });
}
