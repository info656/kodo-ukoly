import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:isar_community/isar.dart';
import 'package:zest/app/data/db.dart';
import 'package:zest/main.dart';
import 'package:zest/app/ui/todos/widgets/todos_action.dart';
import 'package:zest/app/controller/todo_controller.dart';

/// Only text/HTTP(S) URLs are accepted. Receiving a URL never writes a task:
/// the user confirms it in Zest's original task editor.
Map<String, String>? parseKodoShare(Object? value) {
  if (value is! Map) return null;
  final raw = value['text'];
  if (raw is! String || raw.trim().isEmpty || raw.length > 15000) return null;
  final text = raw.trim();
  if (RegExp(
    r'\b(?:javascript|data|file|vbscript|ftp|intent|kodoukoly):',
    caseSensitive: false,
  ).hasMatch(text)) {
    return null;
  }
  if (RegExp(r'\b([a-zA-Z][a-zA-Z0-9+.-]*)://')
      .allMatches(text)
      .any((m) => !['http', 'https'].contains(m.group(1)?.toLowerCase()))) {
    return null;
  }
  final title = value['title'] is String
      ? (value['title'] as String).trim()
      : '';
  final fallback = text.split('\n').first;
  return {
    'title': (title.isEmpty ? fallback : title).substring(
      0,
      (title.isEmpty ? fallback : title).length.clamp(0, 200),
    ),
    'body': text,
  };
}

class KodoShareReceiver extends StatefulWidget {
  final Widget child;
  const KodoShareReceiver({super.key, required this.child});
  @override
  State<KodoShareReceiver> createState() => _KodoShareReceiverState();
}

class _KodoShareReceiverState extends State<KodoShareReceiver> {
  static const channel = MethodChannel('cz.kodo.ukoly/share');
  bool showing = false;
  final pending = <Map<String, String>>[];
  @override
  void initState() {
    super.initState();
    channel.setMethodCallHandler((call) async {
      if (call.method == 'share') receive(call.arguments);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        receive(await channel.invokeMethod('takePending'));
      } on MissingPluginException {
        /*Other desktop platforms have no share extension.*/
      }
    });
  }

  void receive(Object? raw) {
    final data = parseKodoShare(raw);
    if (data == null) return;
    pending.add(data);
    openNext();
  }

  Future<void> openNext() async {
    if (showing || pending.isEmpty || !mounted) return;
    showing = true;
    final group = (await isar.tasks.where().findAll())
        .where((t) => t.remoteKey == 'inbox')
        .firstOrNull;
    if (group != null && mounted) {
      if (!Get.isRegistered<TodoController>()) Get.put(TodoController());
      final payload = pending.removeAt(0);
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => TodosAction(
          text: 'addTodo'.tr,
          edit: false,
          category: false,
          task: group,
          initialTitle: payload['title'],
          initialDescription: payload['body'],
        ),
      );
    }
    showing = false;
    if (group != null && pending.isNotEmpty) unawaited(openNext());
  }

  @override
  void dispose() {
    channel.invokeMethod("pauseReceiver").catchError((Object _) => null);
    channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
