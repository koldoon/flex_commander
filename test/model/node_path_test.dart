import 'package:flex_commander/model/tree/node_path.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NodePath.parse', () {
    test('обычный путь считается путём локальной ФС', () {
      final path = NodePath.parse('/Users/koldoon/Developer');
      expect(path.parts, hasLength(1));
      expect(path.scheme, 'fs');
      expect(path.last.path, '/Users/koldoon/Developer');
    });

    test('явная схема fs разбирается так же', () {
      expect(NodePath.parse('fs:/Users/koldoon'), NodePath.parse('/Users/koldoon'));
    });

    test('вложенный провайдер даёт несколько частей', () {
      final path = NodePath.parse('/Users/k/archive.zip:zip:/subdir/doc.txt');
      expect(path.parts, hasLength(2));
      expect(path.parts.first.scheme, 'fs');
      expect(path.parts.first.path, '/Users/k/archive.zip');
      expect(path.last.scheme, 'zip');
      expect(path.last.path, '/subdir/doc.txt');
    });

    test('двоеточие в имени файла не ломает разбор', () {
      final path = NodePath.parse('/tmp/a:b/c.txt');
      expect(path.parts, hasLength(1));
      expect(path.last.path, '/tmp/a:b/c.txt');
    });

    test('буква диска Windows не считается схемой', () {
      final path = NodePath.parse(r'C:\Users\koldoon');
      expect(path.scheme, 'fs');
      expect(path.last.path, r'C:\Users\koldoon');
    });

    test('одна только схема даёт корень провайдера', () {
      final path = NodePath.parse('sftp:');
      expect(path.scheme, 'sftp');
      expect(path.last.path, '/');
    });
  });

  group('NodePath.toString', () {
    test('схема fs в начале не печатается', () {
      expect(NodePath.local('/Users/koldoon').toString(), '/Users/koldoon');
    });

    test('вложенные провайдеры печатаются со схемой', () {
      const source = '/Users/k/archive.zip:zip:/subdir/doc.txt';
      expect(NodePath.parse(source).toString(), source);
    });

    test('разбор и сборка обратимы', () {
      for (final source in ['/Users/koldoon/Developer', '/tmp/a:b/c.txt', '/Users/k/a.zip:zip:/x/y.txt']) {
        expect(NodePath.parse(source).toString(), source);
      }
    });
  });
}
