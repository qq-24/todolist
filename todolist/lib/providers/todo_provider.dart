import 'dart:async';

import 'package:flutter/material.dart';

import '../models/todo.dart';
import '../services/github_sync_service.dart';
import '../services/local_storage_service.dart';
import '../services/reminder_service.dart';
import 'settings_provider.dart';

/// 同步状态
enum SyncStatus { idle, syncing, success, error }

/// 核心业务状态管理
class TodoProvider extends ChangeNotifier {
  final LocalStorageService _storage = LocalStorageService();
  final GithubSyncService _github = GithubSyncService();
  final ReminderService _reminder = ReminderService();
  final SettingsProvider _settings;

  List<Todo> _todos = [];
  SyncStatus _syncStatus = SyncStatus.idle;
  DateTime? _lastSyncTime;
  DateTime _localUpdatedAt = DateTime(2000);
  Timer? _successTimer;
  Timer? _debounceTimer;
  Timer? _pollTimer; // 定时轮询远端更新
  bool _pendingSync = false;

  // 冲突相关
  TodoFile? _conflictRemoteData;
  String? _conflictRemoteSha;

  TodoProvider(this._settings);

  SyncStatus get syncStatus => _syncStatus;
  DateTime? get lastSyncTime => _lastSyncTime;
  bool get hasConflict => _conflictRemoteData != null;

  /// 根据排序方式返回排序后的列表，已完成的始终沉底
  List<Todo> get sortedTodos {
    final incomplete = _todos.where((t) => !t.completed).toList();
    final completed = _todos.where((t) => t.completed).toList();

    switch (_settings.sortMode) {
      case SortMode.manual:
        incomplete.sort((a, b) => a.sortIndex.compareTo(b.sortIndex));
        completed.sort((a, b) => a.sortIndex.compareTo(b.sortIndex));
      case SortMode.byDeadline:
        incomplete.sort((a, b) {
          if (a.deadline == null && b.deadline == null) return 0;
          if (a.deadline == null) return 1;
          if (b.deadline == null) return -1;
          return a.deadline!.compareTo(b.deadline!);
        });
        completed.sort((a, b) {
          if (a.deadline == null && b.deadline == null) return 0;
          if (a.deadline == null) return 1;
          if (b.deadline == null) return -1;
          return a.deadline!.compareTo(b.deadline!);
        });
    }

    return [...incomplete, ...completed];
  }

  /// 初始化：加载本地数据 + 自动同步
  Future<void> init() async {
    try {
      final local = await _storage.load();
      if (local != null) {
        _todos = local.todos;
        _localUpdatedAt = local.updatedAt;
      }
      notifyListeners();
      await _reminder.rescheduleAll(_todos);
    } on Exception catch (e) {
      print('初始化本地数据失败: $e');
    }
    await sync();
    // 每 30 秒轮询远端更新
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => sync());
  }

  /// 添加任务
  Future<void> addTodo(Todo todo) async {
    todo.sortIndex = _todos.isEmpty
        ? 0
        : _todos.map((t) => t.sortIndex).reduce((a, b) => a > b ? a : b) + 1;
    _todos.add(todo);
    notifyListeners();
    await _saveLocal();
    _debouncedSync();
    await _reminder.scheduleReminder(todo);
  }

  /// 更新任务
  Future<void> updateTodo(Todo todo) async {
    final index = _todos.indexWhere((t) => t.id == todo.id);
    if (index == -1) return;
    todo.updatedAt = DateTime.now();
    _todos[index] = todo;
    notifyListeners();
    await _saveLocal();
    _debouncedSync();
    await _reminder.scheduleReminder(todo);
  }

  /// 删除任务
  Future<void> deleteTodo(String id) async {
    _todos.removeWhere((t) => t.id == id);
    notifyListeners();
    await _saveLocal();
    _debouncedSync();
    await _reminder.cancelReminder(id);
  }

  /// 切换完成状态
  Future<void> toggleComplete(String id) async {
    final index = _todos.indexWhere((t) => t.id == id);
    if (index == -1) return;
    _todos[index].completed = !_todos[index].completed;
    _todos[index].updatedAt = DateTime.now();
    notifyListeners();
    await _saveLocal();
    _debouncedSync();
    await _reminder.rescheduleAll(_todos);
  }

  /// 拖拽排序
  Future<void> reorder(int oldIndex, int newIndex) async {
    final list = sortedTodos;
    if (oldIndex < newIndex) newIndex -= 1;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    for (var i = 0; i < list.length; i++) {
      final todo = _todos.firstWhere((t) => t.id == list[i].id);
      todo.sortIndex = i;
    }
    notifyListeners();
    await _saveLocal();
    _debouncedSync();
  }

  /// 同步逻辑：谁新听谁的
  /// 1. 拉取远端
  /// 2. 比较 updatedAt：远端新 → 拉取覆盖本地；本地新 → 推送覆盖远端；一样 → 跳过
  /// 3. 推送失败 409 → 真正并发冲突，弹窗让用户选
  Future<void> sync() async {
    if (_syncStatus == SyncStatus.syncing) {
      _pendingSync = true;
      return;
    }
    _setSyncStatus(SyncStatus.syncing);

    try {
      final result = await _github.fetch();

      if (result.failed) {
        _setSyncStatus(SyncStatus.error);
        _checkPendingSync();
        return;
      }

      if (result.notFound) {
        // 远端无文件，推送本地
        if (_todos.isNotEmpty) {
          final file = _buildTodoFile();
          final pushResult = await _github.push(file);
          if (pushResult == SyncResult.success) {
            _localUpdatedAt = file.updatedAt;
          }
        }
        _onSyncSuccess();
        _checkPendingSync();
        return;
      }

      // 远端有数据，比较时间戳
      final remoteData = result.data!;
      final remoteSha = result.sha!;

      if (remoteData.updatedAt.isAfter(_localUpdatedAt)) {
        // 远端更新 → 拉取覆盖本地
        _todos = remoteData.todos;
        _localUpdatedAt = remoteData.updatedAt;
        await _storage.save(remoteData);
        await _reminder.rescheduleAll(_todos);
        notifyListeners();
        _onSyncSuccess();
      } else if (_localUpdatedAt.isAfter(remoteData.updatedAt)) {
        // 本地更新 → 推送覆盖远端
        final file = _buildTodoFile();
        final pushResult = await _github.push(file, sha: remoteSha);

        if (pushResult == SyncResult.success) {
          _localUpdatedAt = file.updatedAt;
          _onSyncSuccess();
        } else if (pushResult == SyncResult.conflict) {
          // 推送时 sha 不匹配 → 真正的并发冲突（极罕见）
          final freshResult = await _github.fetch();
          if (!freshResult.failed && freshResult.data != null) {
            _conflictRemoteData = freshResult.data;
            _conflictRemoteSha = freshResult.sha;
          }
          _setSyncStatus(SyncStatus.error);
          notifyListeners();
        } else {
          _setSyncStatus(SyncStatus.error);
        }
      } else {
        // 时间戳一样 → 无需同步
        _onSyncSuccess();
      }

      _checkPendingSync();
    } on Exception catch (e) {
      print('同步异常: $e');
      _setSyncStatus(SyncStatus.error);
      _checkPendingSync();
    }
  }

  /// 解决冲突
  Future<void> resolveConflict(bool keepLocal) async {
    if (keepLocal) {
      final file = _buildTodoFile();
      final pushResult = await _github.push(file, sha: _conflictRemoteSha);
      if (pushResult == SyncResult.success) {
        _localUpdatedAt = file.updatedAt;
      } else {
        // push 失败时保留冲突数据，让用户可以重试
        _setSyncStatus(SyncStatus.error);
        return;
      }
    } else {
      if (_conflictRemoteData != null) {
        _todos = _conflictRemoteData!.todos;
        _localUpdatedAt = _conflictRemoteData!.updatedAt;
        await _storage.save(_conflictRemoteData!);
        await _reminder.rescheduleAll(_todos);
        notifyListeners();
      }
    }
    _conflictRemoteData = null;
    _conflictRemoteSha = null;
    _onSyncSuccess();
  }

  // ── 内部方法 ──

  TodoFile _buildTodoFile() {
    return TodoFile(updatedAt: _localUpdatedAt, todos: _todos);
  }

  /// 保存到本地文件
  Future<void> _saveLocal() async {
    _localUpdatedAt = DateTime.now();
    final file = TodoFile(updatedAt: _localUpdatedAt, todos: _todos);
    try {
      await _storage.save(file);
    } on Exception catch (e) {
      print('本地保存失败: $e');
    }
  }

  /// 防抖触发同步（500ms）
  void _debouncedSync() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      sync();
    });
  }

  void _checkPendingSync() {
    if (_pendingSync) {
      _pendingSync = false;
      Future.delayed(const Duration(milliseconds: 100), () => sync());
    }
  }

  void _setSyncStatus(SyncStatus status) {
    _syncStatus = status;
    notifyListeners();
  }

  void _onSyncSuccess() {
    _lastSyncTime = DateTime.now();
    _setSyncStatus(SyncStatus.success);
    _scheduleSuccessReset();
  }

  void _scheduleSuccessReset() {
    _successTimer?.cancel();
    _successTimer = Timer(const Duration(seconds: 2), () {
      _setSyncStatus(SyncStatus.idle);
    });
  }

  @override
  void dispose() {
    _successTimer?.cancel();
    _debounceTimer?.cancel();
    _pollTimer?.cancel();
    _reminder.dispose();
    super.dispose();
  }
}
