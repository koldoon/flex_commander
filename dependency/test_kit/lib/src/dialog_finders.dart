import 'package:flex_commander/view/dialogs/dialog_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Поле ввода **в окне**, а не любое в приложении.
///
/// Точность здесь не педантизм: внизу окна стоит командная строка, и она тоже
/// поле ввода. `find.byType(TextField)` с её появлением стал находить два, а
/// значит проверял бы то одно, то другое — в зависимости от порядка обхода
/// дерева.
Finder dialogField() => find.descendant(of: find.byType(DialogFrame), matching: find.byType(TextField));
