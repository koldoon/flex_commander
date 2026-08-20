import 'package:fc_api/fc_api.dart';
import 'package:flutter/services.dart' as services;

/// Буфер обмена системы.
class SystemClipboard implements ClipboardService {
  const SystemClipboard();

  @override
  Future<void> writeText(String text) => services.Clipboard.setData(services.ClipboardData(text: text));

  @override
  Future<String?> readText() async {
    final data = await services.Clipboard.getData(services.Clipboard.kTextPlain);
    return data?.text;
  }
}
