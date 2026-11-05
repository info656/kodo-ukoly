import 'package:isar_community/isar.dart';
import 'package:zest/app/data/db.dart';
import 'package:zest/main.dart';
import 'package:zest/kodo/store.dart';

class TodoRepository {
  final Isar _isar = isar;

  // ==================== CREATE ====================

  Future<Todos> create({
    required String name,
    required String description,
    required DateTime? completedTime,
    required bool fix,
    required Priority priority,
    required List<String> tags,
    required int index,
    required Tasks task,
    Todos? parent,
  }) async {
    return KodoStore.instance.createTodo(
      group: task,
      title: name,
      body: description,
      metadata: {
        'due': completedTime?.toUtc().toIso8601String(),
        'pinned': fix,
        'priority': priority.name,
        'tags': tags,
        'index': index,
        'parent': parent?.remoteKey,
      },
    );
  }

  // ==================== READ ====================

  Future<List<Todos>> getAll() async {
    return await _isar.todos.where().sortByIndex().findAll();
  }

  Future<Todos?> getById(int id) async {
    return await _isar.todos.get(id);
  }

  Future<List<Todos>> getByTaskId(int taskId) async {
    return await _isar.todos
        .filter()
        .task((q) => q.idEqualTo(taskId))
        .sortByIndex()
        .findAll();
  }

  Future<List<Todos>> getChildren(int parentId) async {
    return await _isar.todos
        .filter()
        .parent((q) => q.idEqualTo(parentId))
        .sortByIndex()
        .findAll();
  }

  // ==================== UPDATE ====================

  Future<void> update(Todos todo) => KodoStore.instance.saveTodo(todo);
  Future<void> updateStatusWithSubtasks({
    required Todos parentTodo,
    required TodoStatus status,
  }) async {
    final ids = <int>{};
    final stack = <Todos>[parentTodo];
    while (stack.isNotEmpty) {
      final t = stack.removeLast();
      if (!ids.add(t.id)) continue;
      stack.addAll(await getChildren(t.id));
    }
    for (final id in ids) {
      final t = await getById(id);
      if (t != null) {
        t.status = status;
        await KodoStore.instance.saveTodo(t, fields: false);
      }
    }
  }

  Future<void> updateFields({
    required Todos todo,
    required String name,
    required String description,
    required DateTime? completedTime,
    required bool fix,
    required Priority priority,
    required List<String> tags,
    required Tasks task,
  }) async {
    todo.name = name;
    todo.description = description;
    todo.todoCompletedTime = completedTime;
    todo.fix = fix;
    todo.priority = priority;
    todo.tags = tags;
    await KodoStore.instance.saveTodo(todo, group: task);
  }

  Future<void> moveToTask({required Set todoIds, required Tasks task}) async {
    for (final id in todoIds) {
      final t = await getById(id as int);
      if (t != null) {
        t.parent.value = null;
        await KodoStore.instance.moveTodo(t, task);
      }
    }
  }

  Future<void> moveToParent({
    required Set<int> todoIds,
    required Todos? newParent,
    required Tasks? newTask,
  }) async {
    for (final id in todoIds) {
      var t = await getById(id);
      if (t == null) continue;
      if (newTask != null && newTask.remoteKey != t.task.value?.remoteKey) {
        t.parent.value = null;
        await KodoStore.instance.moveTodo(t, newTask);
        t = await getById(id);
      }
      if (t != null) {
        t.parent.value = newParent;
        await update(t);
      }
    }
  }

  Future<void> updateIndexes(List<Todos> todos) async {
    for (var i = 0; i < todos.length; i++) {
      final t = await getById(todos[i].id);
      if (t != null) {
        t.index = i;
        await update(t);
      }
    }
  }

  Future<void> delete(int id) async {
    final t = await getById(id);
    if (t != null) await KodoStore.instance.removeTodo(t);
  }

  Future<void> deleteBatch(Set<int> ids) async {
    for (final id in ids) {
      await delete(id);
    }
  }

  // ==================== WATCH ====================

  Stream<void> watchLazy() {
    return _isar.todos.watchLazy();
  }
}
