import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/todo.dart';
import 'windows_notification_service.dart';

/// 跨平台提醒调度服务
/// Android：原生 AlarmManager + BroadcastReceiver 弹通知
/// Windows：Dart Timer + print（App 前台有效）
class ReminderService {
  static const _channel = MethodChannel('com.mingh.todolist/alarm');
  final Map<String, Timer> _timers = {};
  final Set<String> _scheduledTodoIds = {}; // 追踪已调度的 todoId
  WindowsNotificationService? _winNotifier;

  void setWindowsNotifier(WindowsNotificationService notifier) {
    _winNotifier = notifier;
  }

  /// 为一个任务调度所有选中的提前量提醒
  Future<void> scheduleReminder(Todo todo) async {
    await _cancelAllForTodo(todo.id);

    if (!todo.remind || todo.deadline == null || todo.completed) return;
    _scheduledTodoIds.add(todo.id);

    for (final advance in todo.reminderAdvances) {
      DateTime time;
      if (advance == ReminderAdvance.morning7) {
        // 当天早上 7 点
        time = DateTime(todo.deadline!.year, todo.deadline!.month, todo.deadline!.day, 7);
      } else {
        time = todo.deadline!.subtract(advance.offset);
      }
      if (time.isBefore(DateTime.now())) continue;

      final id = _notificationId(todo.id, advance);
      final message = '${advance.label}: ${todo.title}';

      if (Platform.isAndroid) {
        try {
          await _channel.invokeMethod('setAlarm', {
            'triggerAtMillis': time.millisecondsSinceEpoch,
            'message': message,
            'id': id,
            'todoId': todo.id,
            'vibrationMode': todo.vibrationMode.name,
          });
        } on PlatformException catch (e) {
          debugPrint('设置闹钟失败: $e');
        }
      } else if (Platform.isWindows) {
        final delay = time.difference(DateTime.now());
        final timerKey = '${todo.id}_${advance.name}';
        _timers[timerKey] = Timer(delay, () {
          _winNotifier?.showReminder(todo, message);
        });
      }
    }
  }

  Future<void> cancelReminder(String todoId) async {
    _scheduledTodoIds.remove(todoId);
    await _cancelAllForTodo(todoId);
  }

  Future<void> rescheduleAll(List<Todo> todos) async {
    // 取消不在新列表中的旧闹钟（Android 端）
    final newIds = todos.where((t) => t.remind && !t.completed && t.deadline != null)
        .map((t) => t.id).toSet();
    final removedIds = _scheduledTodoIds.difference(newIds);
    for (final id in removedIds) {
      await _cancelAllForTodo(id);
    }
    _scheduledTodoIds.clear();

    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    for (final todo in todos) {
      if (todo.remind && !todo.completed && todo.deadline != null) {
        await scheduleReminder(todo);
      }
    }
  }

  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }

  /// 关闭指定任务的活跃通知/浮窗/震动
  Future<void> dismissActiveNotification(String todoId) async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('dismissNotification', {'todoId': todoId});
      } on PlatformException catch (e) {
        debugPrint('关闭通知失败: $e');
      }
    } else if (Platform.isWindows) {
      _winNotifier?.dismissNotification(todoId);
    }
  }

  /// 立即发送一个测试通知（调试用）
  Future<void> testNotification() async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('testNotification');
      } on PlatformException catch (e) {
        debugPrint('测试通知失败: $e');
      }
    } else if (Platform.isWindows) {
      _winNotifier?.showTest();
    }
  }

  // FNV-1a 确定性哈希（与 Kotlin 端一致，UTF-8 编码）
  int _notificationId(String todoId, ReminderAdvance advance) {
    return _fnvHash('${todoId}_${advance.name}');
  }

  int _snoozeId(String todoId) {
    return _fnvHash('${todoId}_snooze');
  }

  // FNV-1a 确定性哈希（与 Kotlin 端一致，UTF-8 编码）
  int _fnvHash(String input) {
    final bytes = utf8.encode(input);
    var h = 0x811c9dc5;
    for (final b in bytes) {
      h = h ^ b;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h & 0x7FFFFFFF;
  }

  Future<void> _cancelAllForTodo(String todoId) async {
    _winNotifier?.cancelSnooze(todoId);
    for (final advance in ReminderAdvance.values) {
      final id = _notificationId(todoId, advance);
      if (Platform.isAndroid) {
        try {
          await _channel.invokeMethod('cancelAlarm', {'id': id});
        } on PlatformException catch (e) {
          debugPrint('取消闹钟失败: $e');
        }
      }
      final timerKey = '${todoId}_${advance.name}';
      _timers[timerKey]?.cancel();
      _timers.remove(timerKey);
    }
    // 取消稍后提醒的闹钟（独立 hash，与 advance 无关）
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('cancelAlarm', {'id': _snoozeId(todoId)});
      } on PlatformException catch (e) {
        debugPrint('取消 snooze 闹钟失败: $e');
      }
    }
  }
}
