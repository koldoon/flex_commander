import 'package:fc_content_types/fc_content_types.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

/// Колонка «Type» в собранном приложении (`docs/spec/content-types.md`, §2а).
void main() {
  late AppRuntime runtime;

  setUp(() async {
    runtime = await testApp(
      provider: InMemoryTreeProvider([FakeEntry.directory('/home'), FakeEntry.file('/home/photo.dat', size: 64)])
        ..home = '/home',
      modules: featureModules(),
    );
    await runtime.app.start();
  });

  test('колонка объявлена, но по умолчанию невидима', () {
    final column = runtime.app.columns.find(ContentTypeDetection.column.id);

    expect(column, isNotNull, reason: 'модуль её объявляет');
    expect(column!.visible, isFalse, reason: 'показать её — значит читать байты у всех видимых файлов');
    expect(column.sortable, isFalse, reason: 'тип — знание экранное, ядру сравнивать нечем');
  });

  test('щелчок по её заголовку порядка не меняет', () async {
    final was = runtime.app.left.sort;

    await runtime.app.left.sortBy(ContentTypeDetection.column.id);

    expect(runtime.app.left.sort, was, reason: 'несортируемая колонка щелчка не принимает');
  });
}
