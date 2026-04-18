import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

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
  ReminderService get reminder => _reminder;
  final SettingsProvider _settings;

  List<Todo> _todos = [];
  SyncStatus _syncStatus = SyncStatus.idle;
  TodoKind _currentKind = TodoKind.task;
  DateTime? _lastSyncTime;
  DateTime _localUpdatedAt = DateTime(2000);
  Timer? _successTimer;
  Timer? _debounceTimer;
  Timer? _pollTimer; // 定时轮询远端更新
  bool _pendingSync = false;
  bool _syncing = false; // 独立并发锁，与 UI 展示用的 _syncStatus 解耦
  String? _lastPushHash; // 防重复推送
  int _syncErrorCount = 0; // 连续错误计数
  String? _lastError; // 最近一次错误信息

  // 冲突相关
  TodoFile? _conflictRemoteData;
  String? _conflictRemoteSha;

  TodoProvider(this._settings);

  SyncStatus get syncStatus => _syncStatus;
  DateTime? get lastSyncTime => _lastSyncTime;
  bool get hasConflict => _conflictRemoteData != null;
  String? get lastError => _lastError;
  TodoFile? get conflictRemoteData => _conflictRemoteData;

  TodoKind get currentKind => _currentKind;
  void setKind(TodoKind kind) {
    if (_currentKind == kind) return;
    _currentKind = kind;
    notifyListeners();
  }

  /// 各类型的未完成数量
  int countByKind(TodoKind kind) => _todos.where((t) => !t.completed && t.kind == kind).length;

  /// 已完成的心愿列表（做过的合集用）
  List<Todo> get completedWishes =>
      _todos.where((t) => t.kind == TodoKind.wish && t.completed).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  /// 根据排序方式返回排序后的列表，已完成的始终沉底，按 currentKind 过滤
  List<Todo> get sortedTodos {
    final ofKind = _todos.where((t) => t.kind == _currentKind).toList();
    final incomplete = ofKind.where((t) => !t.completed).toList();
    final completed = ofKind.where((t) => t.completed).toList();

    switch (_settings.sortMode) {
      case SortMode.manual:
        incomplete.sort((a, b) => a.sortIndex.compareTo(b.sortIndex));
      case SortMode.byDeadline:
        incomplete.sort((a, b) {
          if (a.deadline == null && b.deadline == null) return 0;
          if (a.deadline == null) return 1;
          if (b.deadline == null) return -1;
          return a.deadline!.compareTo(b.deadline!);
        });
      case SortMode.byCreatedTime:
        incomplete.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }

    // 已完成：最新完成的在最上面（按 updatedAt 降序）
    completed.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return [...incomplete, ...completed];
  }

  /// 心愿升级为任务
  Future<void> promoteToTask(String id, {DateTime? deadline}) async {
    final index = _todos.indexWhere((t) => t.id == id);
    if (index == -1) return;
    _todos[index] = _todos[index].copyWith(
      kind: TodoKind.task,
      deadline: deadline,
      updatedAt: DateTime.now(),
    );
    notifyListeners();
    await _saveLocal();
    _debouncedSync();
    if (deadline != null) await _reminder.scheduleReminder(_todos[index]);
  }

  /// 任务降级为心愿（清除时间相关字段）
  Future<void> demoteToWish(String id) async {
    final index = _todos.indexWhere((t) => t.id == id);
    if (index == -1) return;
    await _reminder.cancelReminder(id);
    _todos[index] = _todos[index].copyWith(
      kind: TodoKind.wish,
      deadline: null,
      remind: false,
      repeatMode: TodoRepeatMode.none,
      updatedAt: DateTime.now(),
    );
    notifyListeners();
    await _saveLocal();
    _debouncedSync();
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
    await processPendingActions();
    // 每 30 秒轮询远端更新（有修改时临时切到 5 秒）
    _startPolling();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    final interval = 30;
    _pollTimer = Timer.periodic(Duration(seconds: interval), (_) => sync());
  }

  void pausePolling() { _pollTimer?.cancel(); }
  void resumePolling() { _startPolling(); }

  /// 处理原生悬浮窗写入的 pending 操作（完成任务、稍后提醒）
  Future<void> processPendingActions() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      bool changed = false;

      // 处理完成（rename 到临时文件再读取，避免跨进程竞态）
      final completeFile = File('${dir.path}/pending_complete.txt');
      if (completeFile.existsSync()) {
        final tmpFile = File('${dir.path}/pending_complete.tmp');
        if (tmpFile.existsSync()) tmpFile.deleteSync();
        completeFile.renameSync(tmpFile.path);
        final ids = tmpFile.readAsLinesSync().where((s) => s.isNotEmpty).toSet();
        tmpFile.deleteSync();
        for (final todoId in ids) {
          final idx = _todos.indexWhere((t) => t.id == todoId);
          if (idx != -1 && !_todos[idx].completed) {
            final t = _todos[idx];
            if (t.repeatMode != TodoRepeatMode.none && t.deadline != null) {
              _todos[idx] = t.copyWith(
                deadline: t.repeatMode.nextOccurrence(t.deadline!, originalDay: t.originalDeadlineDay),
                updatedAt: DateTime.now(),
              );
            } else {
              _todos[idx] = t.copyWith(completed: true, updatedAt: DateTime.now());
            }
            changed = true;
          }
        }
      }

      // 处理稍后提醒（rename 到临时文件再读取）
      final snoozeFile = File('${dir.path}/pending_snooze.txt');
      if (snoozeFile.existsSync()) {
        final tmpSnooze = File('${dir.path}/pending_snooze.tmp');
        if (tmpSnooze.existsSync()) tmpSnooze.deleteSync();
        snoozeFile.renameSync(tmpSnooze.path);
        final lines = tmpSnooze.readAsLinesSync().where((s) => s.contains('|'));
        tmpSnooze.deleteSync();
        for (final line in lines) {
          final parts = line.split('|');
          final todoId = parts[0];
          final snoozeMs = int.tryParse(parts[1]);
          if (snoozeMs != null) {
            final idx = _todos.indexWhere((t) => t.id == todoId);
            if (idx != -1) {
              _todos[idx] = _todos[idx].copyWith(
                deadline: DateTime.fromMillisecondsSinceEpoch(snoozeMs),
                updatedAt: DateTime.now(),
              );
              changed = true;
            }
          }
        }
      }

      if (changed) {
        notifyListeners();
        await _saveLocal();
        _debouncedSync();
        await _reminder.rescheduleAll(_todos);
      }
    } on Exception catch (e) {
      debugPrint('处理 pending 操作失败: $e');
    }
  }

  /// 添加任务
  Future<void> addTodo(Todo todo) async {
    todo.sortIndex = _todos.isEmpty
        ? 0
        : _todos.map((t) => t.sortIndex).reduce((a, b) => a > b ? a : b) + 1;
    if (todo.deadline != null && todo.originalDeadlineDay == null) {
      todo.originalDeadlineDay = todo.deadline!.day;
    }
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
    if (todo.deadline != null && todo.originalDeadlineDay == null) {
      todo.originalDeadlineDay = todo.deadline!.day;
    }
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
    final todo = _todos[index];

    if (!todo.completed && todo.repeatMode != TodoRepeatMode.none && todo.deadline != null) {
      // 重复任务：推截止时间到下一周期，不标记完成
      _todos[index] = todo.copyWith(
        deadline: todo.repeatMode.nextOccurrence(todo.deadline!, originalDay: todo.originalDeadlineDay),
        updatedAt: DateTime.now(),
      );
    } else {
      _todos[index] = todo.copyWith(completed: !todo.completed, updatedAt: DateTime.now());
    }

    notifyListeners();
    await _saveLocal();
    sync(); // 完成任务立即同步（不走防抖，让另一端尽快收到）
    await _reminder.rescheduleAll(_todos);
  }

  /// 拖拽排序（只更新未完成任务的 sortIndex）
  Future<void> reorder(int oldIndex, int newIndex) async {
    final incomplete = sortedTodos.where((t) => !t.completed).toList();
    if (oldIndex >= incomplete.length || newIndex > incomplete.length) return;
    if (oldIndex < newIndex) newIndex -= 1;
    final item = incomplete.removeAt(oldIndex);
    incomplete.insert(newIndex, item);
    for (var i = 0; i < incomplete.length; i++) {
      final todo = _todos.firstWhere((t) => t.id == incomplete[i].id);
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
    if (_syncing) {
      _pendingSync = true;
      return;
    }
    _syncing = true;
    _setSyncStatus(SyncStatus.syncing);

    try {
      final snapshotAt = _localUpdatedAt; // 快照：检测 sync 期间是否有本地修改
      final result = await _github.fetch();

      if (result.failed) {
        _lastError = result.errorMessage ?? '网络错误';
        _setSyncStatus(SyncStatus.error);
        _checkPendingSync();
        return;
      }

      if (result.notFound) {
        // 远端无文件，推送本地
        if (_todos.isNotEmpty) {
          final file = _buildTodoFile();
          final pushResult = await _github.push(file);
          if (pushResult.type == SyncResultType.success) {
            _localUpdatedAt = file.updatedAt;
            _onSyncSuccess();
          } else {
            _lastError = pushResult.errorMessage ?? '推送失败';
            _setSyncStatus(SyncStatus.error);
          }
        } else {
          _onSyncSuccess();
        }
        _checkPendingSync();
        return;
      }

      // 远端有数据，比较时间戳
      final remoteData = result.data!;
      final remoteSha = result.sha!;

      if (remoteData.updatedAt.isAfter(_localUpdatedAt)) {
        // 远端更新 → 拉取覆盖本地（但先检查 sync 期间是否有本地修改）
        if (_localUpdatedAt != snapshotAt) {
          // sync 期间用户修改了数据，放弃覆盖，重新同步
          _pendingSync = true;
          _onSyncSuccess();
          _checkPendingSync();
          return;
        }
        // 对比新旧数据，关闭被远端操作过的任务的通知
        final oldMap = {for (final t in _todos) t.id: t};
        final dismissIds = <String>{};
        for (final rt in remoteData.todos) {
          final lt = oldMap[rt.id];
          if (lt == null) continue;
          // 远端刚完成
          if (!lt.completed && rt.completed) dismissIds.add(rt.id);
          // 远端 deadline 变了（稍后提醒/编辑）
          if (lt.deadline != rt.deadline) dismissIds.add(rt.id);
        }
        for (final id in dismissIds) {
          await _reminder.dismissActiveNotification(id);
        }
        // 再次检查：dismiss 期间用户可能修改了数据
        if (_localUpdatedAt != snapshotAt) {
          _pendingSync = true;
          _onSyncSuccess();
          _checkPendingSync();
          return;
        }
        _todos = remoteData.todos;
        _localUpdatedAt = remoteData.updatedAt;
        await _storage.save(remoteData);
        await _reminder.rescheduleAll(_todos);
        notifyListeners();
        _onSyncSuccess();
      } else if (_localUpdatedAt.isAfter(remoteData.updatedAt)) {
        // 本地更新 → 推送覆盖远端
        final file = _buildTodoFile();
        // 防重复推送：hash 比对
        final hash = _storage.computeHash(file);
        if (hash == _lastPushHash) {
          _onSyncSuccess();
          _checkPendingSync();
          return;
        }
        final pushResult = await _github.push(file, sha: remoteSha);

        if (pushResult.type == SyncResultType.success) {
          _localUpdatedAt = file.updatedAt;
          _lastPushHash = hash;
          _onSyncSuccess();
        } else if (pushResult.type == SyncResultType.conflict) {
          // 推送时 sha 不匹配 → 真正的并发冲突（极罕见）
          final freshResult = await _github.fetch();
          if (!freshResult.failed && freshResult.data != null) {
            _conflictRemoteData = freshResult.data;
            _conflictRemoteSha = freshResult.sha;
          }
          _lastError = '同步冲突';
          _setSyncStatus(SyncStatus.error);
          notifyListeners();
        } else {
          _lastError = pushResult.errorMessage ?? '推送失败';
          _setSyncStatus(SyncStatus.error);
        }
      } else {
        // 时间戳一样 → 无需同步
        _onSyncSuccess();
      }

      _checkPendingSync();
    } on Exception catch (e) {
      print('同步异常: $e');
      _lastError = '同步异常: $e';
      _setSyncStatus(SyncStatus.error);
      _checkPendingSync();
    } finally {
      _syncing = false;
    }
  }

  /// 解决冲突，返回是否成功
  Future<bool> resolveConflict(bool keepLocal) async {
    if (keepLocal) {
      final file = _buildTodoFile();
      final pushResult = await _github.push(file, sha: _conflictRemoteSha);
      if (pushResult.type == SyncResultType.success) {
        _localUpdatedAt = file.updatedAt;
      } else {
        // push 失败，重新 fetch 获取最新 SHA 以便重试
        final freshResult = await _github.fetch();
        if (!freshResult.failed && freshResult.sha != null) {
          _conflictRemoteSha = freshResult.sha;
          _conflictRemoteData = freshResult.data;
        } else {
          // re-fetch 也失败，清除冲突状态让下次 sync 重新走正常流程
          _conflictRemoteData = null;
          _conflictRemoteSha = null;
        }
        _lastError = '冲突解决失败';
        _setSyncStatus(SyncStatus.error);
        return false;
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
    return true;
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
      _lastError = '本地保存失败';
      _setSyncStatus(SyncStatus.error);
    }
  }

  /// 防抖触发同步（500ms）+ 临时提高轮询频率
  void _debouncedSync() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      sync();
    });
    // 有修改时临时切到 5 秒轮询，30 秒后恢复
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => sync());
    Future.delayed(const Duration(seconds: 30), _startPolling);
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
    if (status == SyncStatus.error) {
      _syncErrorCount++;
    }
  }

  void _onSyncSuccess() {
    _syncErrorCount = 0;
    _lastError = null;
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
