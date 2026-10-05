import 'package:xml/xml.dart';

import 's3_encoding.dart';

/// Ответы хранилища — XML (`docs/spec/s3.md`, §4).
///
/// Разбор — по локальным именам элементов, без пространства имён: MinIO, AWS и
/// Google Storage пишут его по-разному, а смысл один.

/// Корзина.
class S3Bucket {
  const S3Bucket({required this.name, this.created});

  final String name;
  final DateTime? created;
}

/// Объект в листинге.
class S3Object {
  const S3Object({required this.key, required this.size, this.modified, this.etag});

  final String key;
  final int size;
  final DateTime? modified;
  final String? etag;
}

/// Страница листинга: объекты, префиксы и токен следующей страницы.
class S3Page {
  const S3Page({required this.objects, required this.prefixes, this.nextToken});

  final List<S3Object> objects;

  /// Общие префиксы — «каталоги» уровня. Уже раскодированы.
  final List<String> prefixes;

  /// Токен следующей страницы; null — страниц больше нет.
  final String? nextToken;

  bool get truncated => nextToken != null;
}

/// Ошибка из тела ответа.
class S3ErrorBody {
  const S3ErrorBody({required this.code, this.message = '', this.region, this.key});

  final String code;
  final String message;

  /// Регион, который называет сервер, когда подписали не тем.
  final String? region;
  final String? key;
}

/// Ключ, который не удалось удалить пачкой.
class S3DeleteFailure {
  const S3DeleteFailure({required this.key, required this.code, this.message = ''});

  final String key;
  final String code;
  final String message;
}

XmlDocument _parse(String xml) => XmlDocument.parse(xml);

Iterable<XmlElement> _children(XmlElement parent, String name) =>
    parent.childElements.where((element) => element.name.local == name);

String? _text(XmlElement parent, String name) {
  for (final element in _children(parent, name)) {
    return element.innerText;
  }
  return null;
}

DateTime? _date(String? value) => value == null || value.isEmpty ? null : DateTime.tryParse(value);

/// `ListAllMyBucketsResult`.
List<S3Bucket> parseBuckets(String xml) {
  final root = _parse(xml).rootElement;
  return [
    for (final list in _children(root, 'Buckets'))
      for (final bucket in _children(list, 'Bucket'))
        if (_text(bucket, 'Name') case final name? when name.isNotEmpty)
          S3Bucket(name: name, created: _date(_text(bucket, 'CreationDate'))),
  ];
}

/// `ListBucketResult` версии 2.
///
/// Верхний `<Prefix>` — это **запрошенный** префикс, а не каталог: префиксы
/// уровня — только внутри `<CommonPrefixes>`. Перепутать — значит показать
/// каталог внутри самого себя (разведка §3).
///
/// Ключи и префиксы раскодируются, только если ответ сказал
/// `<EncodingType>url</EncodingType>`: иначе они приехали сырыми, и `+` в них —
/// настоящий плюс.
S3Page parseListV2(String xml) {
  final root = _parse(xml).rootElement;
  final encoded = _text(root, 'EncodingType') == 'url';
  String decode(String value) => encoded ? decodeListingValue(value) : value;

  final truncated = _text(root, 'IsTruncated') == 'true';
  final token = _text(root, 'NextContinuationToken');
  return S3Page(
    objects: [
      for (final content in _children(root, 'Contents'))
        if (_text(content, 'Key') case final key?)
          S3Object(
            key: decode(key),
            size: int.tryParse(_text(content, 'Size') ?? '') ?? 0,
            modified: _date(_text(content, 'LastModified')),
            etag: _text(content, 'ETag'),
          ),
    ],
    prefixes: [
      for (final common in _children(root, 'CommonPrefixes'))
        if (_text(common, 'Prefix') case final prefix?) decode(prefix),
    ],
    nextToken: truncated && token != null && token.isNotEmpty ? token : null,
  );
}

/// `<Error>` — и в ответах с ошибкой, и в тех, где сервер ответил 200, а внутри
/// всё же ошибка (итог многочастной загрузки, копия). null — это не ошибка.
S3ErrorBody? parseError(String xml) {
  if (!xml.contains('<Error')) {
    return null;
  }
  final XmlElement root;
  try {
    root = _parse(xml).rootElement;
  } on XmlException {
    return null;
  }
  if (root.name.local != 'Error') {
    return null;
  }
  return S3ErrorBody(
    code: _text(root, 'Code') ?? '',
    message: _text(root, 'Message') ?? '',
    region: _text(root, 'Region'),
    key: _text(root, 'Key'),
  );
}

/// `InitiateMultipartUploadResult/UploadId`.
String parseUploadId(String xml) => _text(_parse(xml).rootElement, 'UploadId') ?? '';

/// `DeleteResult`: ключи, которые удалить не вышло.
List<S3DeleteFailure> parseDeleteResult(String xml) {
  final root = _parse(xml).rootElement;
  return [
    for (final error in _children(root, 'Error'))
      S3DeleteFailure(
        key: _text(error, 'Key') ?? '',
        code: _text(error, 'Code') ?? '',
        message: _text(error, 'Message') ?? '',
      ),
  ];
}

/// Часть многочастной загрузки.
class S3Part {
  const S3Part({required this.number, required this.etag});

  final int number;
  final String etag;
}

/// Тело `CompleteMultipartUpload`: части по номерам.
String completeXml(List<S3Part> parts) {
  final sorted = [...parts]..sort((a, b) => a.number.compareTo(b.number));
  final builder = XmlBuilder();
  builder.element(
    'CompleteMultipartUpload',
    nest: () {
      for (final part in sorted) {
        builder.element(
          'Part',
          nest: () {
            builder.element('PartNumber', nest: '${part.number}');
            builder.element('ETag', nest: part.etag);
          },
        );
      }
    },
  );
  return builder.buildDocument().toXmlString();
}

/// Тело `DeleteObjects`: тихо — в ответе только ошибки.
String deleteXml(List<String> keys) {
  final builder = XmlBuilder();
  builder.element(
    'Delete',
    nest: () {
      builder.element('Quiet', nest: 'true');
      for (final key in keys) {
        builder.element('Object', nest: () => builder.element('Key', nest: key));
      }
    },
  );
  return builder.buildDocument().toXmlString();
}
