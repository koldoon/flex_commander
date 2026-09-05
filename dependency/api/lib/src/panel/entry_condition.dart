import '../protocol/file_entry.dart';
import '../util/file_mask.dart';

/// Условие, под которое строка списка либо подходит, либо нет.
///
/// Одно на всех, кто раскрашивает и украшает список: правило иконки
/// (`spec/file-icons.md`) и правило цвета (`spec/file-colors.md`) отличаются
/// только тем, что дают, — а спрашивают одно и то же. Два похожих типа с двумя
/// разборами JSON были бы двумя местами, где чинить одну и ту же ошибку.
///
/// **Все заданные условия складываются по «и».** Незаданные (`null`) не
/// проверяются вовсе: условие без единого поля подходит любой строке.
class EntryCondition {
  EntryCondition({
    this.mask,
    this.kinds,
    this.hidden,
    this.executable,
    this.broken,
    this.scheme,
    this.contentType,
    this.contentGroup,
  }) : _mask = mask == null ? null : FileMask.parse(mask);

  /// Образцы имён через `;`, как их пишут в настройках: `*.dart;!*.g.dart`.
  ///
  /// Строкой, а не разобранной маской: то же значение уезжает обратно в файл
  /// настроек, а `FileMask` исходных образцов не помнит.
  final String? mask;

  final Set<EntryKind>? kinds;
  final bool? hidden;
  final bool? executable;
  final bool? broken;

  /// Откуда строка: `fs`, `zip`, `sftp`.
  final String? scheme;

  /// Тип по содержимому: `png`, `zip` (`spec/content-types.md`).
  ///
  /// Именами, а не значениями: тип живёт в API интерфейса, а сюда, к значениям
  /// границы, ему хода нет. Спрашивающий и так держит его в руках — он и
  /// передаёт имя в [matches].
  final Set<String>? contentType;

  /// Семья типа: `image`, `archive`, `executable`.
  final Set<String>? contentGroup;

  final FileMask? _mask;

  /// Нужно ли для проверки заглянуть внутрь файла.
  ///
  /// По этому спрашивающий понимает, что условие не проверить, пока тип не
  /// определён, — и что определение стоит завести.
  bool get needsContent => contentType != null || contentGroup != null;

  /// Подходит ли строка.
  ///
  /// [type] и [group] — то, что известно о содержимом **сейчас**. Условие,
  /// которое о содержимом спрашивает, а ответа не получило, не подходит: пусть
  /// сработает следующее правило, а это проверится заново, когда тип приедет.
  bool matches(FileEntry entry, {String? type, String? group}) {
    if (_mask != null && !_mask.matches(entry.name)) {
      return false;
    }
    if (kinds != null && !kinds!.contains(entry.kind)) {
      return false;
    }
    if (hidden != null && entry.hidden != hidden) {
      return false;
    }
    if (executable != null && entry.executable != executable) {
      return false;
    }
    if (broken != null && entry.broken != broken) {
      return false;
    }
    if (scheme != null && entry.scheme != scheme) {
      return false;
    }
    if (contentType != null && (type == null || !contentType!.contains(type))) {
      return false;
    }
    if (contentGroup != null && (group == null || !contentGroup!.contains(group))) {
      return false;
    }
    return true;
  }

  /// Разбор записи из файла настроек.
  ///
  /// Неизвестное имя вида строки отбрасывается, а не роняет разбор: файл
  /// правят руками. Отброшены все — условие подойдёт нулю строк, и правило
  /// просто не сработает; это честнее, чем сделать вид, будто про вид строки
  /// не спрашивали вовсе.
  factory EntryCondition.fromJson(Map<String, Object?> json) {
    Set<String>? names(Object? source) {
      if (source is String) {
        return {source};
      }
      if (source is List) {
        return {
          for (final item in source)
            if (item is String) item,
        };
      }
      return null;
    }

    final kinds = names(json['kinds']);

    return EntryCondition(
      mask: json['mask'] is String ? json['mask'] as String : null,
      kinds:
          kinds == null
              ? null
              : {
                for (final name in kinds)
                  for (final kind in EntryKind.values)
                    if (kind.name == name) kind,
              },
      hidden: json['hidden'] is bool ? json['hidden'] as bool : null,
      executable: json['executable'] is bool ? json['executable'] as bool : null,
      broken: json['broken'] is bool ? json['broken'] as bool : null,
      scheme: json['scheme'] is String ? json['scheme'] as String : null,
      contentType: names(json['contentType']),
      contentGroup: names(json['contentGroup']),
    );
  }

  Map<String, Object?> toJson() => {
    if (mask != null) 'mask': mask,
    if (kinds != null) 'kinds': [for (final kind in kinds!) kind.name],
    if (hidden != null) 'hidden': hidden,
    if (executable != null) 'executable': executable,
    if (broken != null) 'broken': broken,
    if (scheme != null) 'scheme': scheme,
    if (contentType != null) 'contentType': [...contentType!],
    if (contentGroup != null) 'contentGroup': [...contentGroup!],
  };
}
