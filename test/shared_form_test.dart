import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:zest/app/controller/todo_controller.dart';
import 'package:zest/app/data/db.dart';
import 'package:zest/app/ui/todos/widgets/todos_action.dart';
import 'package:zest/main.dart' as app;

class ControlledTasks extends TodoController {
  Completer<Todos>? _save;
  Completer<Todos> get save => _save ??= Completer<Todos>();
  int attempts = 0;
  @override
  void onInit() {}
  @override
  Future<Todos> addTodo({
    required Tasks task,
    required String title,
    required String description,
    required String time,
    required bool pinned,
    required Priority priority,
    required List<String> tags,
    Todos? parent,
  }) {
    attempts++;
    return save.future;
  }
}

void main() {
  late ControlledTasks tasks;
  setUp(() {
    Get.testMode = true;
    app.settings = Settings();
    tasks = ControlledTasks();
    Get.put<TodoController>(tasks);
  });
  tearDown(() async {
    await Get.deleteAll(force: true);
    Get.reset();
  });
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final inbox = Tasks(title: 'Inbox', taskColor: 0xFF607D8B)
      ..remoteKey = 'inbox';
    await tester.pumpWidget(
      GetMaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => TodosAction(
                  text: 'New task',
                  edit: false,
                  category: false,
                  task: inbox,
                  initialTitle: 'Shared article',
                  initialDescription: 'https://example.com/article',
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'shared form can save immediately and waits for server confirmation',
    (tester) async {
      await open(tester);
      expect(find.text('Shared article'), findsOneWidget);
      await tester.tap(find.text('ready'));
      await tester.pump();
      expect(tasks.attempts, 1);
      expect(find.text('Shared article'), findsOneWidget);
      await tester.tap(find.text('ready'));
      await tester.pump();
      expect(tasks.attempts, 1);
      tasks.save.complete(
        Todos(name: 'Shared article', createdTime: DateTime(2026, 11, 5)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TodosAction), findsNothing);
    },
  );
  testWidgets('failed online save keeps the original input in the editor', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('ready'));
    await tester.pump();
    expect(tasks.attempts, 1);
    tasks.save.completeError(StateError('Synthetic network failure'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(find.byType(TodosAction), findsOneWidget);
    expect(find.text('Shared article'), findsOneWidget);
    expect(find.text('https://example.com/article'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
