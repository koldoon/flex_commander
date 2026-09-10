import 'dart:convert';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import 'attribute_edits.dart';
import 'mode_edit.dart';

/// Что набрано в окне правки атрибутов и что из этого выйдет.
///
/// Поверх [FcAsyncRun]: ход дела, вопросы при отказах, уход в фон и разбор
/// ошибки — общие для всех длительных работ и достаются готовыми. Своё здесь
/// одно — что именно правим.
class AttributesRun extends FcAsyncRun {
  AttributesRun({
    required super.app,
    required super.commandId,
    required super.title,
    required super.failureMessage,
    required super.show,
    required this.targets,
  });

  /// Строки, которые правят. Приезжают полностью после показа окна.
  List<FileEntry> targets;

  /// Атрибуты первой цели — прочитанные заново.
  ///
  /// Из них берутся умения источника, даты, владелец и расширенные атрибуты.
  /// Пока не приехали — форма показывает поля погашенными.
  NodeAttributes sample = NodeAttributes.unknown;

  /// Сетка прав: что было и что стало.
  ModeEdit initialMode = ModeEdit();
  ModeEdit mode = ModeEdit();

  bool loading = true;

  /// Набранное в полях — строками: их правят, а не выбирают.
  String modifiedText = '';
  String accessedText = '';
  String ownerText = '';
  String groupText = '';

  /// Что стало с расширенными атрибутами: имя → новое значение.
  final Map<String, List<int>> xattrSet = {};
  final Set<String> xattrRemove = {};

  /// Новый атрибут — тот, что набирают в последней, пустой строке.
  String newXattrName = '';
  String newXattrValue = '';

  bool recursive = false;
  AttributeScope applyTo = AttributeScope.all;

  /// Правят один объект — тогда видны даты, владелец и расширенные атрибуты.
  ///
  /// У нескольких они бессмысленны: «дата изменения» у пятнадцати файлов — это
  /// не сведение, а каша. Правило то же, что у окна сведений.
  bool get single => targets.length == 1;

  /// Есть ли среди целей каталог: без него рекурсии не бывает.
  bool get hasDirectory => targets.any((entry) => entry.isDirectory);

  /// Что показывать в восьмеричном поле; пусто — биты расходятся.
  String get octalText {
    final value = mode.octal;
    return value == null ? '' : value.toRadixString(8).padLeft(4, '0');
  }

  /// Расширенные атрибуты объекта с учётом того, что с ними сделали.
  List<Xattr> get xattrs => [
    for (final one in sample.xattrs)
      if (!xattrRemove.contains(one.name)) Xattr(one.name, xattrSet[one.name] ?? one.value),
    for (final one in xattrSet.entries)
      if (!sample.xattrs.any((old) => old.name == one.key)) Xattr(one.key, one.value),
  ];

  /// Прочитанное у источника: умения, значения полей, исходная сетка прав.
  ///
  /// Свежие атрибуты спрашиваются у **первой** цели: у неё же берутся умения
  /// источника. Сетка прав при одной цели строится по ним, при нескольких — по
  /// тому, что уже показано в списке. Спрашивать заново про каждую из десяти
  /// тысяч помеченных строк значило бы столько же разговоров через границу, а
  /// сетке от них нужно ровно одно — совпал бит или нет.
  void adopt(NodeAttributes attributes, {required List<int> modes}) {
    sample = attributes;
    loading = false;
    initialMode = ModeEdit.of(modes);
    mode = ModeEdit.of(modes);
    modifiedText = _formatDate(attributes.modified);
    accessedText = _formatDate(attributes.accessed);
    ownerText = attributes.owner.isEmpty ? (attributes.uid?.toString() ?? '') : attributes.owner;
    groupText = attributes.group.isEmpty ? (attributes.gid?.toString() ?? '') : attributes.group;
    notifyListeners();
  }

  /// Спросить не вышло: показываем причину вместо полей.
  void failed(FsError failure) {
    loading = false;
    error = failure.message;
    notifyListeners();
  }

  void setBit(int bit, bool? value) {
    mode.set(bit, value);
    notifyListeners();
  }

  /// Набранное восьмеричное — тот же частный случай пары масок.
  ///
  /// Негодное не роняет и не стирает сетку: набирают по одной цифре, и
  /// незаконченное число — обычное состояние поля.
  void setOctal(String text) {
    final value = int.tryParse(text.trim(), radix: 8);
    if (value == null || value > AttributeEdits.modeMask) {
      return;
    }
    mode.setOctal(value);
    notifyListeners();
  }

  void setModified(String value) => modifiedText = value;

  void setAccessed(String value) => accessedText = value;

  void setOwner(String value) => ownerText = value;

  void setGroup(String value) => groupText = value;

  void setNewXattrName(String value) => newXattrName = value;

  void setNewXattrValue(String value) => newXattrValue = value;

  /// Новое значение атрибута.
  ///
  /// [wasBinary] — значение было двоичным, и в поле стояла пустота с подсказкой
  /// «binary». Пустое поле там означает «не трогать», а не «сделать пустым»:
  /// иначе один взгляд на окно стирал бы то, чего человек не видел.
  void setXattr(String name, String value, {bool wasBinary = false}) {
    if (wasBinary && value.isEmpty) {
      xattrSet.remove(name);
    } else {
      xattrSet[name] = utf8.encode(value);
    }
    xattrRemove.remove(name);
    notifyListeners();
  }

  void removeXattr(String name) {
    xattrSet.remove(name);
    xattrRemove.add(name);
    notifyListeners();
  }

  void addXattr() {
    final name = newXattrName.trim();
    if (name.isEmpty) {
      return;
    }
    xattrSet[name] = utf8.encode(newXattrValue);
    xattrRemove.remove(name);
    newXattrName = '';
    newXattrValue = '';
    notifyListeners();
  }

  void setRecursive(bool value) {
    recursive = value;
    notifyListeners();
  }

  void setApplyTo(AttributeScope value) {
    applyTo = value;
    notifyListeners();
  }

  /// Собрать правку. null — в полях негодное, и об этом сказано в [error].
  AttributeEdits? collect(Strings strings) {
    error = null;
    final changes = mode.changesFrom(initialMode);

    DateTime? date(String text, DateTime? was) {
      if (!single || text.trim().isEmpty || text == _formatDate(was)) {
        return null;
      }
      final parsed = _parseDate(text.trim());
      if (parsed == null) {
        error = strings.tr('Wrong date: {text}', args: {'text': text});
      }
      return parsed;
    }

    int? number(String text, {required String was, required int? id}) {
      if (!single || text.trim().isEmpty || text.trim() == was) {
        return null;
      }
      final typed = text.trim();
      final parsed = int.tryParse(typed);
      if (parsed != null) {
        return parsed;
      }
      // Разрешить чужое имя в число некому: словарь пользователей живёт у
      // источника, по эту сторону границы его нет. Своё имя мы знаем — оно
      // приехало вместе с числом; всё прочее приходится набирать числом.
      error = strings.tr('Unknown user: {name}', args: {'name': typed});
      return id;
    }

    final modified = date(modifiedText, sample.modified);
    final accessed = date(accessedText, sample.accessed);
    final uid = number(
      ownerText,
      was: sample.owner.isEmpty ? (sample.uid?.toString() ?? '') : sample.owner,
      id: sample.uid,
    );
    final gid = number(
      groupText,
      was: sample.group.isEmpty ? (sample.gid?.toString() ?? '') : sample.group,
      id: sample.gid,
    );

    if (error != null) {
      notifyListeners();
      return null;
    }

    return AttributeEdits(
      setBits: changes.setBits,
      clearBits: changes.clearBits,
      modified: modified,
      accessed: accessed,
      uid: uid,
      gid: gid,
      xattrSet: single ? Map.of(xattrSet) : const {},
      xattrRemove: single ? xattrRemove.toList() : const [],
      recursive: recursive && hasDirectory,
      applyTo: applyTo,
    );
  }

  /// Дата в том же виде, в каком её показывают сведения.
  static String _formatDate(DateTime? at) {
    if (at == null) {
      return '';
    }
    String two(int value) => value.toString().padLeft(2, '0');
    return '${at.year}-${two(at.month)}-${two(at.day)} ${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
  }

  /// Разбор той же записи. Своего календаря окно не заводит: дату файла ставят
  /// редко и обычно списывают откуда-то, а не выбирают мышью.
  static DateTime? _parseDate(String text) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?$').firstMatch(text);
    if (match == null) {
      return null;
    }
    final parts = [for (var i = 1; i <= 6; i++) int.tryParse(match.group(i) ?? '0') ?? 0];
    final at = DateTime(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]);
    // `DateTime` перекидывает через край молча: 32 января станет 1 февраля.
    // Спрошенное и полученное должны совпадать, иначе это не та дата.
    return at.month == parts[1] && at.day == parts[2] ? at : null;
  }
}
