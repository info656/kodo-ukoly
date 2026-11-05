import 'package:flutter/material.dart';
import 'package:isar_community/isar.dart';
import 'package:zest/app/data/db.dart';
import 'package:zest/main.dart';
import 'package:zest/kodo/store.dart';

class TaskRepository {
  final Isar _isar = isar;

  // ==================== CREATE ====================

  Future<Tasks> create({
    required String title,
    required String description,
    required Color color,
    required int index,
  }) async {
    return KodoStore.instance.addGroup(title, description, color, index);
  }

  // ==================== READ ====================

  Future<List<Tasks>> getAll() async {
    return await _isar.tasks.where().sortByIndex().findAll();
  }

  Future<Tasks?> getById(int id) async {
    return await _isar.tasks.get(id);
  }

  Future<bool> existsByTitle(String title) async {
    final count = await _isar.tasks.filter().titleEqualTo(title).count();
    return count > 0;
  }

  // ==================== UPDATE ====================

  Future<void> update(Tasks task) => KodoStore.instance.group(task);
  Future<void> updateFields({
    required Tasks task,
    required String title,
    required String description,
    required Color color,
  }) async {
    task.title = title;
    task.description = description;
    task.taskColor = color.toARGB32();
    await update(task);
  }

  Future<void> updateArchiveStatus(Tasks task, bool archived) async {
    task.archive = archived;
    await update(task);
  }

  Future<void> updateArchiveStatusBatch(
    List<Tasks> tasks,
    bool archived,
  ) async {
    for (final task in tasks) {
      await updateArchiveStatus(task, archived);
    }
  }

  Future<void> updateIndexes(List<Tasks> tasks) async {
    for (var i = 0; i < tasks.length; i++) {
      final task = await getById(tasks[i].id);
      if (task != null) {
        task.index = i;
        await update(task);
      }
    }
  }

  Future<void> delete(Tasks task) =>
      KodoStore.instance.group(task, hidden: true);

  // ==================== WATCH ====================

  Stream<void> watchLazy() {
    return _isar.tasks.watchLazy();
  }
}
