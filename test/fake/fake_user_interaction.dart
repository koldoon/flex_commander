import 'package:flex_commander/model/app/user_interaction.dart';

/// Диалоги в памяти: запоминают, о чём спросили, и отвечают заранее заданным.
class FakeUserInteraction implements UserInteraction {
  FakeUserInteraction({this.answer, this.confirmed = true});

  /// Что «введёт» пользователь; null — откажется.
  String? answer;

  /// Что ответит на подтверждение.
  bool confirmed;

  final List<String> prompts = [];
  final List<String> confirmations = [];
  final List<String> errors = [];

  @override
  Future<String?> promptText({
    required String title,
    String initialText = '',
    String? hint,
    String confirmLabel = 'OK',
  }) async {
    prompts.add(title);
    return answer;
  }

  @override
  Future<bool> confirm({required String title, String? message, String confirmLabel = 'OK'}) async {
    confirmations.add(title);
    return confirmed;
  }

  @override
  Future<void> showError({required String title, String? message}) async {
    errors.add(message == null ? title : '$title: $message');
  }
}
