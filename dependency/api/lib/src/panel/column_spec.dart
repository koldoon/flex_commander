import '../serialization.dart';

enum ColumnAlign { start, end }

/// Колонка панели: и объявление, и запись человеческого выбора.
///
/// Два прочтения одного значения, и различать их важно.
///
/// * **Объявление** приносит модуль (`registry.column`): в нём заполнено всё —
///   заголовок, ширина, выравнивание, сортируемость. Это ответ на вопрос
///   «какая эта колонка бывает».
/// * **Запись раскладки** приходит из настроек (`ColumnLayout.fromJson`): в ней
///   осмысленны только [id], [visible] и — если человек тянул за край —
///   [width]. Остальные поля стоят умолчаниями и ничего не значат до тех пор,
///   пока раскладку не наложат на объявления ([ColumnLayout.resolvedWith]).
///
/// Тип один, потому что после наложения получается ровно он же — и дальше
/// ездит в `PanelState`, рисуется таблицей и возвращается обратно
/// (`docs/spec/column-registry.md`, §3).
class ColumnSpec {
  const ColumnSpec({
    required this.id,
    this.title = '',
    this.width = 0,
    this.minWidth = 24,
    this.visible = true,
    this.pinned = false,
    this.flexible = false,
    this.sortable = true,
    this.align = ColumnAlign.start,
    this.inLayout = true,
    this.ownWidth = false,
  });

  /// Имя колонки — в настройках, в протоколе и в справке.
  ///
  /// Строка, а не перечислимое: колонки приносят модули, и знать их наперёд
  /// некому. Имена штатных колонок (`name`, `size`, `modified`…) сохранены с
  /// тех пор, когда перечисление ещё было, — старые настройки читаются без
  /// миграции. Колонка модуля живёт в своём пространстве имён: `fs.owner`,
  /// `content.type`.
  final String id;

  /// Заголовок — по-английски, как всё в коде: это ключ перевода
  /// (`docs/spec/localization.md`, §3). Пусто — заголовка нет вовсе (значок).
  final String title;

  /// Ширина в логических пикселях. У «резиновой» колонки не значит ничего.
  final double width;

  final double minWidth;

  final bool visible;

  /// Колонку нельзя скрыть и нельзя увести с места: значок и имя.
  ///
  /// Без них строка нечитаема, а ширину им задаёт оформление — поэтому из
  /// настроек она и не берётся (см. [ColumnLayout.fromJson]).
  final bool pinned;

  /// Колонка занимает всё оставшееся место. Сегодня такова одна — имя.
  final bool flexible;

  /// По колонке можно сортировать.
  final bool sortable;

  final ColumnAlign align;

  /// Колонка входит в раскладку панели.
  ///
  /// false — колонка есть, но человек её не выбирает и в меню видимости она не
  /// стоит: её ставит себе вид, которому она принадлежит. Такова ветвь дерева
  /// — таблица ветвей не рисует, и предлагать её в списке колонок было бы
  /// обещанием несбыточного. Объявлена она при этом наравне со всеми: и
  /// ячейка, и сравнение у неё те же, что у любой другой
  /// (`docs/spec/column-registry.md`, §7).
  final bool inLayout;

  /// Ширину задал человек, а не объявление.
  ///
  /// Различие нужно затем, чтобы правка оформления доходила до тех, у кого уже
  /// есть `settings.json`: неправленая ширина в файл не пишется вовсе и
  /// приезжает из объявления каждый раз заново. Иначе однажды сохранённое
  /// число осталось бы навсегда — та же беда, от которой закреплённые колонки
  /// защищены отдельным правилом.
  final bool ownWidth;

  ColumnSpec copyWith({double? width, bool? visible, bool? ownWidth}) => ColumnSpec(
    id: id,
    title: title,
    width: width ?? this.width,
    minWidth: minWidth,
    visible: visible ?? this.visible,
    pinned: pinned,
    flexible: flexible,
    sortable: sortable,
    align: align,
    inLayout: inLayout,
    ownWidth: ownWidth ?? this.ownWidth,
  );

  @override
  String toString() => 'ColumnSpec($id, $width, visible: $visible)';
}

/// Раскладка колонок панели: чем человек переопределил объявленное.
///
/// Неизменяема: любое изменение даёт новую раскладку.
///
/// Умолчаний в ней нет и быть не может — их знает объявление, а объявления
/// приносят модули. Пустая раскладка означает «как объявлено», а не «колонок
/// нет» (`docs/spec/column-registry.md`, §4).
class ColumnLayout {
  ColumnLayout(List<ColumnSpec> columns) : columns = List.unmodifiable(columns);

  static final ColumnLayout empty = ColumnLayout(const []);

  final List<ColumnSpec> columns;

  List<ColumnSpec> get visibleColumns => columns.where((c) => c.visible).toList(growable: false);

  ColumnSpec? find(String id) {
    for (final column in columns) {
      if (column.id == id) {
        return column;
      }
    }
    return null;
  }

  int indexOf(String id) => columns.indexWhere((column) => column.id == id);

  /// Первая позиция, куда можно перетащить колонку: закреплённые колонки
  /// (значок и имя) всегда остаются слева.
  int get firstMovableIndex {
    var index = 0;
    for (var i = 0; i < columns.length; i++) {
      if (columns[i].pinned) {
        index = i + 1;
      }
    }
    return index;
  }

  /// Переставляет колонку так, чтобы её итоговая позиция стала [to].
  /// Закреплённые колонки не двигаются и не пропускают другие вперёд себя.
  ColumnLayout moveColumn(int from, int to) {
    if (from == to || from < 0 || from >= columns.length || columns[from].pinned) {
      return this;
    }

    final result = columns.toList();
    final spec = result.removeAt(from);
    result.insert(to.clamp(firstMovableIndex, result.length), spec);
    return ColumnLayout(result);
  }

  ColumnLayout resize(String id, double width) {
    return ColumnLayout([
      for (final column in columns)
        column.id == id
            ? column.copyWith(width: width < column.minWidth ? column.minWidth : width, ownWidth: true)
            : column,
    ]);
  }

  ColumnLayout toggleVisible(String id) {
    return ColumnLayout([
      for (final column in columns)
        column.id == id && !column.pinned ? column.copyWith(visible: !column.visible) : column,
    ]);
  }

  /// Объявленное, переставленное и подправленное этой раскладкой.
  ///
  /// Считает тот, кто рисует: реестр объявлений живёт на его стороне
  /// (`docs/spec/column-registry.md`, §4.1). Порядок берётся из раскладки;
  /// объявления, которых в ней нет, дописываются в конец — так новая колонка
  /// появляется у того, у кого настройки давно есть.
  ///
  /// [extra] — колонки, без которых не читается показанный источник
  /// (`PanelExtraColumns`): их включают поверх раскладки, никуда не сохраняя.
  ///
  /// Идентификатор, которого никто не объявил, **пропускается, но не
  /// теряется**: рисовать его нечем, а вернуть его в настройки обязано
  /// слияние ([merge]).
  ColumnLayout resolvedWith(Iterable<ColumnSpec> declared, {Set<String> extra = const {}}) {
    final byId = {
      for (final column in declared)
        if (column.inLayout) column.id: column,
    };
    final result = <ColumnSpec>[];

    for (final saved in columns) {
      final spec = byId.remove(saved.id);
      if (spec == null) {
        continue;
      }
      result.add(_apply(spec, saved, extra));
    }
    for (final spec in byId.values) {
      result.add(_apply(spec, null, extra));
    }
    return ColumnLayout(result);
  }

  /// Объявление под записью раскладки.
  ///
  /// Ширина закреплённой колонки из раскладки не берётся никогда, ширина
  /// прочих — только если человек её и правда менял ([ColumnSpec.ownWidth]).
  static ColumnSpec _apply(ColumnSpec spec, ColumnSpec? saved, Set<String> extra) {
    final visible = extra.contains(spec.id) || (spec.pinned ? true : saved?.visible ?? spec.visible);
    if (saved == null || spec.pinned || !saved.ownWidth) {
      return spec.copyWith(visible: visible);
    }
    return spec.copyWith(width: saved.width, visible: visible, ownWidth: true);
  }

  /// Эта раскладка, поверх которой легло то, что вернул экран.
  ///
  /// Экран видит только объявленное и возвращает только его; колонка
  /// выключенного модуля до него не доходила и обязана уцелеть. Поэтому
  /// порядок берётся из пришедшего, а хранившееся, которого в нём нет,
  /// дописывается следом — в прежнем порядке между собой. То же правило, по
  /// которому переживает запись чужой раздел настроек
  /// (`docs/spec/column-registry.md`, §4.3).
  ColumnLayout merge(ColumnLayout incoming) {
    final arrived = {for (final column in incoming.columns) column.id};
    return ColumnLayout([
      ...incoming.columns,
      for (final column in columns)
        if (!arrived.contains(column.id)) column,
    ]);
  }

  /// В файл уходит только то, что человек менял руками.
  ///
  /// Ширина — если он тянул за край ([ColumnSpec.ownWidth]) и колонка не
  /// закреплена: у значка ручки нет, имя резиновое, а числа им задаёт
  /// оформление. Иначе однажды сохранённое значение осталось бы навсегда, и
  /// правки оформления до пользователя не дошли бы.
  List<Map<String, Object?>> toJson() => [
    for (final column in columns)
      {'id': column.id, if (!column.pinned && column.ownWidth) 'width': column.width, 'visible': column.visible},
  ];

  /// Восстановление раскладки из настроек.
  ///
  /// Никаких умолчаний: читается ровно то, что в файле. Незнакомая запись не
  /// выбрасывается — она **спит**: выключенный на один запуск модуль не должен
  /// стирать раскладку (`docs/spec/column-registry.md`, §4.2).
  factory ColumnLayout.fromJson(Object? json) {
    if (json is! List) {
      return empty;
    }

    final restored = <ColumnSpec>[];
    for (final item in json) {
      if (item is! Map) {
        continue;
      }
      final id = extract('', item['id']);
      if (id.isEmpty) {
        continue;
      }
      final width = item['width'];
      restored.add(
        ColumnSpec(id: id, width: extract(0.0, width), visible: extract(true, item['visible']), ownWidth: width is num),
      );
    }
    return ColumnLayout(restored);
  }
}
