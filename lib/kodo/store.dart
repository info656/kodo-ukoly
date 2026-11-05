import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:isar_community/isar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:zest/app/data/db.dart';
import 'package:zest/main.dart';
import 'package:zest/app/utils/snackbar_overlay.dart';

/// The original UI reads Isar. This is a replaceable view cache, never an outbox.
/// Every business write goes to the authenticated server before changing cache.
class KodoStore {
  KodoStore._();
  static final instance = KodoStore._();
  SupabaseClient get api => Supabase.instance.client;
  final files = <String, List<Map<String, dynamic>>>{};
  final _pendingCreates = <String, String>{};
  final _meta = <String, Map<String, dynamic>>{};
  Future<void>? _refresh;
  bool ready = false;

  Future<void> refresh() =>
      _refresh ??= _load().whenComplete(() => _refresh = null);
  int _epoch = 0;
  Future<void> refreshAfterWrite() async {
    await _refresh;
    await refresh();
  }

  Future<void> _load() async {
    final epoch = _epoch;
    final value = Map<String, dynamic>.from(
      await api.rpc('kodo_tasks_app_read'),
    );
    if (value['schema'] != 1 || value['owner'] != api.auth.currentUser?.id) {
      throw StateError('Odpověď nepatří přihlášenému účtu.');
    }
    if (epoch != _epoch || api.auth.currentUser?.id != value['owner']) return;
    final groups = (value['groups'] as List).cast<Map>();
    final items = (value['items'] as List).cast<Map>();
    final oldGroups = await isar.tasks.where().findAll();
    final oldItems = await isar.todos.where().findAll();
    final categories = <String, Tasks>{};
    final todos = <String, Todos>{};
    final newMeta = <String, Map<String, dynamic>>{};
    final newFiles = <String, List<Map<String, dynamic>>>{};
    await isar.writeTxn(() async {
      for (var i = 0; i < groups.length; i++) {
        final row = groups[i], key = row['key'] as String;
        final m = Map<String, dynamic>.from(row['meta'] as Map? ?? {});
        newMeta[key] = m;
        final prior = oldGroups.where((g) => g.remoteKey == key).firstOrNull;
        final group =
            prior ?? Tasks(title: row['name'] as String, taskColor: 0xFF607D8B);
        group.remoteKey = key;
        group.remoteVersion = row['version'] as String;
        group.title = m['title'] as String? ?? row['name'] as String;
        group.description = m['description'] as String? ?? '';
        group.taskColor = (m['color'] as num?)?.toInt() ?? 0xFF607D8B;
        group.index = (m['index'] as num?)?.toInt() ?? i;
        group.archive = m['archive'] == true;
        group.isSystem = key == 'inbox';
        group.sortOption =
            SortOption.values.where((v) => v.name == m['sort']).firstOrNull ??
            SortOption.none;
        await isar.tasks.put(group);
        categories[key] = group;
      }
      for (final row in items) {
        final key = row['key'] as String, group = categories[row['group']];
        if (group == null) continue;
        final m = Map<String, dynamic>.from(row['meta'] as Map? ?? {});
        newMeta[key] = m;
        final prior = oldItems.where((t) => t.remoteKey == key).firstOrNull;
        final todo =
            prior ??
            Todos(
              name: row['title'] as String,
              createdTime: DateTime.parse(row['created_at'] as String),
            );
        todo.remoteKey = key;
        todo.remoteVersion = row['version'] as String;
        todo.name = row['title'] as String;
        todo.description = m['empty_body_value'] == row['body']
            ? ''
            : row['body'] as String;
        todo.todoCompletionTime = DateTime.tryParse(
          row['completed_at'] as String? ?? '',
        );
        todo.status = row['completed_at'] == null
            ? TodoStatus.active
            : m['status'] == 'cancelled'
            ? TodoStatus.cancelled
            : TodoStatus.done;
        todo.todoCompletedTime = DateTime.tryParse(m['due'] as String? ?? '');
        todo.fix = m['pinned'] == true;
        todo.priority =
            Priority.values.where((p) => p.name == m['priority']).firstOrNull ??
            Priority.none;
        todo.childrenSortOption =
            SortOption.values.where((v) => v.name == m['sort']).firstOrNull ??
            SortOption.none;
        todo.tags = (m['tags'] as List? ?? [])
            .map((v) => v.toString())
            .toList();
        todo.index = (m['index'] as num?)?.toInt();
        todo.task.value = group;
        await isar.todos.put(todo);
        await todo.task.save();
        todos[key] = todo;
        newFiles[key] = (row['files'] as List? ?? [])
            .map((v) => Map<String, dynamic>.from(v as Map))
            .toList();
      }
      for (final entry in todos.entries) {
        entry.value.parent.value = todos[newMeta[entry.key]?['parent']];
        await entry.value.parent.save();
      }
      await isar.todos.deleteAll(
        oldItems
            .where((t) => !todos.containsKey(t.remoteKey))
            .map((t) => t.id)
            .toList(),
      );
      await isar.tasks.deleteAll(
        oldGroups
            .where((g) => !categories.containsKey(g.remoteKey))
            .map((g) => g.id)
            .toList(),
      );
      settings.defaultCategorySeeded = true;
      settings.defaultCategoryId ??= categories['inbox']?.id;
      await isar.settings.put(settings);
    });
    _meta
      ..clear()
      ..addAll(newMeta);
    files
      ..clear()
      ..addAll(newFiles);
    if (epoch == _epoch) ready = true;
  }

  Map<String, dynamic> meta(String? key) => Map.of(_meta[key] ?? {});
  Map<String, dynamic> todoMeta(Todos t) => {
    ...meta(t.remoteKey),
    'due': t.todoCompletedTime?.toUtc().toIso8601String(),
    'pinned': t.fix,
    'priority': t.priority.name,
    'tags': t.tags,
    'index': t.index,
    'sort': t.childrenSortOption.name,
    'status': t.status.name,
    'parent': t.parent.value?.remoteKey,
  };
  Future<String> write(
    String action,
    String key,
    String? version,
    Map<String, dynamic> payload,
  ) async {
    if (!ready || api.auth.currentSession == null) {
      throw StateError('Nejprve se přihlaste a načtěte úkoly.');
    }
    try {
      final result = Map<String, dynamic>.from(
        await api.rpc(
          'kodo_tasks_app_write',
          params: {
            'action_value': action,
            'key_value': key,
            'expected_value': version,
            'payload_value': payload,
          },
        ),
      );
      return result['key'] as String;
    } catch (e) {
      // Discard optimistic widget changes and re-read authority when possible.
      try {
        await refreshAfterWrite();
      } catch (_) {}
      SnackBarOverlay.instance.show(
        e is PostgrestException
            ? e.message
            : 'Změna se neuložila. Zkontrolujte internet.',
        isError: true,
      );
      rethrow;
    }
  }

  Future<Todos> createTodo({
    required Tasks group,
    required String title,
    required String body,
    required Map<String, dynamic> metadata,
  }) async {
    final groupKey = group.remoteKey;
    if (groupKey == null) throw StateError('Skupina není připojená.');
    final fingerprint = jsonEncode([
      api.auth.currentUser?.id,
      groupKey,
      title,
      body,
      metadata,
    ]);
    final key = _pendingCreates.putIfAbsent(
      fingerprint,
      () => '${groupKey == 'inbox' ? 'inbox' : 'task'}:${const Uuid().v4()}',
    );
    await write('create', key, null, {
      'group': groupKey,
      'title': title,
      'body': body,
      'meta': metadata,
    });
    await refreshAfterWrite();
    final result = (await isar.todos.where().findAll()).firstWhere(
      (t) => t.remoteKey == key,
    );
    _pendingCreates.remove(fingerprint);
    return result;
  }

  Future<void> saveTodo(Todos t, {Tasks? group, bool fields = true}) async {
    final key = t.remoteKey;
    if (key == null) throw StateError('Úkol není připojený.');
    final nextGroup = group ?? t.task.value;
    if (fields) {
      await write('put', key, t.remoteVersion, {
        'title': t.name,
        'body': t.description,
        'meta': todoMeta(t),
      });
    } else {
      await write('status', key, t.remoteVersion, {
        'status': t.status.name,
        'meta': todoMeta(t),
      });
    }
    await refreshAfterWrite();
    final refreshed = await isar.todos.get(t.id);
    if (refreshed != null &&
        nextGroup?.remoteKey != refreshed.task.value?.remoteKey) {
      await moveTodo(refreshed, nextGroup!);
    }
  }

  Future<void> moveTodo(Todos t, Tasks group) async {
    final key = await write('move', t.remoteKey!, t.remoteVersion, {
      'group': group.remoteKey,
      'meta': todoMeta(t),
    });
    if (key != t.remoteKey) {
      // Keep UI navigation stable when the server assigns an inbox item to a client.
      t.remoteKey = key;
      await isar.writeTxn(() => isar.todos.put(t));
    }
    await refreshAfterWrite();
  }

  Future<void> removeTodo(Todos t) async {
    await write('delete', t.remoteKey!, t.remoteVersion, {});
    await refreshAfterWrite();
  }

  Future<void> group(Tasks t, {bool hidden = false}) async {
    await write('group', t.remoteKey!, t.remoteVersion, {
      'meta': {
        ...meta(t.remoteKey),
        'title': t.title,
        'description': t.description,
        'color': t.taskColor,
        'index': t.index,
        'sort': t.sortOption.name,
        'archive': t.archive,
        'hidden': hidden,
      },
    });
    await refreshAfterWrite();
  }

  Future<Tasks> addGroup(
    String title,
    String description,
    Color color,
    int index,
  ) async {
    final key = await write('group_create', 'inbox', null, {
      'title': title,
      'meta': {
        'description': description,
        'color': color.toARGB32(),
        'index': index,
      },
    });
    await refreshAfterWrite();
    return (await isar.tasks.where().findAll()).firstWhere(
      (t) => t.remoteKey == key,
    );
  }

  Future<void> clear() async {
    _epoch++;
    ready = false;
    try {
      await _refresh;
    } catch (_) {}
    files.clear();
    _meta.clear();
    _pendingCreates.clear();
    await isar.writeTxn(() async {
      await isar.todos.clear();
      await isar.tasks.clear();
    });
  }
}
