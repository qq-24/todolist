import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/todo.dart';

/// 跨平台提醒调度服务
/// Android：原生 AlarmManager + BroadcastReceiver 弹通知
/// Windows：Dart Timer + print（App 前台有效）
class ReminderService {
  static const _channel = MethodChannel('com.mingh.todolist/alarm');
  final Map<String, Timer> _timers = {};

  /// 为一个任务调度所有选中的提前量提醒
  Future<void> scheduleReminder(Todo todo) async {
    await _cancelAllForTodo(todo.id);

    if (!todo.remind || todo.deadline == null || todo.completed) return;

    for (final advance in todo.reminderAdvances) {
      final time = todo.deadline!.subtract(advance.offset);
      if (time.isBefore(DateTime.now())) continue;

      final id = _notificationId(todo.id, advance);
      final message = '${advance.label}: ${todo.title}';

      if (Platform.isAndroid) {
        try {
          await _channel.invokeMethod('setAlarm', {
            'triggerAtMillis': time.millisecondsSinceEpoch,
            'message': message,
            'id': id,
            'vibrationMode': todo.vibrationMode.name,
          });
        } on PlatformException catch (e) {
          debugPrint('设置闹钟失败: $e');
        }
      } else if (Platform.isWindows) {
        final delay = time.difference(DateTime.now());
        final timerKey = '${todo.id}_${advance.name}';
        _timers[timerKey] = Timer(delay, () {
          debugPrint('⏰ 任务提醒: $message');
        });
      }
    }
  }

  Future<void> cancelReminder(String todoId) async {
    await _cancelAllForTodo(todoId);
  }

  Future<void> rescheduleAll(List<Todo> todos) async {
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

  /// 立即发送一个测试通知（调试用）
  Future<void> testNotification() async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('testNotification');
      } on PlatformException catch (e) {
        debugPrint('测试通知失败: $e');
      }
    }
  }

  int _notificationId(String todoId, ReminderAdvance advance) {
    return ('${todoId}_${advance.name}'.hashCode.abs()) % 2147483647;
  }

  Future<void> _cancelAllForTodo(String todoId) async {
    for (final advance in ReminderAdvance.values) {
      final id = _notificationId(todoId, advance);
      if (Platform.isAndroid) {
        try {
          await _channel.invokeMethod('cancelAlarm', {'id': id});
          // 同时取消稍后提醒的闹钟（id+100000）
          await _channel.invokeMethod('cancelAlarm', {'id': id + 100000});
        } on PlatformException catch (e) {
          debugPrint('取消闹钟失败: $e');
        }
      }
      final timerKey = '${todoId}_${advance.name}';
      _timers[timerKey]?.cancel();
      _timers.remove(timerKey);
    }
  }
}
