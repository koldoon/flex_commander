import 'package:fc_api/fc_api.dart';

/// Что история помнит между запусками — только свою глубину: сами записи
/// живут сеанс (`docs/spec/operation-history.md`, §11).
class HistorySettings implements Serializable {
  HistorySettings({this.depth = defaultDepth});

  /// Сколько работ помнится.
  ///
  /// Полсотни — это заведомо больше, чем помнит человек: отменяют последнюю, а
  /// список читают, чтобы понять, что вообще происходило.
  static const int defaultDepth = 50;
  static const int minDepth = 1;
  static const int maxDepth = 500;

  int depth;

  @override
  void fromMap(Map<String, dynamic> m) {
    depth = extract(depth, m['depth']).clamp(minDepth, maxDepth);
  }

  @override
  void toMap(Map<String, dynamic> m) {
    m['depth'] = depth;
  }
}
