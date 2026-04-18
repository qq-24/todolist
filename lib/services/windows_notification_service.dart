import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:window_manager/window_manager.dart';

import '../models/todo.dart';
import '../providers/todo_provider.dart';

/// 通知点击时需要聚焦的任务 ID
final focusTodoNotifier = ValueNotifier<String?>(null);

/// Windows Toast 通知服务
class WindowsNotificationService {
  final TodoProvider _todoProvider;
  final Map<String, Timer> _snoozeTimers = {};
  final Map<String, LocalNotification> _activeNotifications = {};

  WindowsNotificationService(this._todoProvider);

  Future<void> init() async {
    await localNotifier.setup(
      appName: 'Todo',
      shortcutPolicy: ShortcutPolicy.requireCreate,
    );
  }

  void showReminder(Todo todo, String message) {
    _activeNotifications[todo.id]?.close(); // 关闭同 todoId 的旧通知
    final notification = LocalNotification(
      title: '任务提醒',
      body: message,
      actions: [
        LocalNotificationAction(text: '完成'),
        LocalNotificationAction(text: '稍后提醒'),
      ],
    );

    notification.onClick = () {
      focusTodoNotifier.value = todo.id;
      windowManager.show();
      windowManager.focus();
    };

    notification.onClickAction = (actionIndex) {
      if (actionIndex == 0) {
        _todoProvider.toggleComplete(todo.id);
      } else if (actionIndex == 1) {
        // 15分钟后重新通知（追踪 Timer 以便取消）
        _snoozeTimers[todo.id]?.cancel();
        _snoozeTimers[todo.id] = Timer(const Duration(minutes: 15), () {
          _snoozeTimers.remove(todo.id);
          showReminder(todo, '稍后提醒: ${todo.title}');
        });
      }
    };

    notification.show();
    _activeNotifications[todo.id] = notification;
  }

  void dismissNotification(String todoId) {
    _activeNotifications[todoId]?.close();
    _activeNotifications.remove(todoId);
    cancelSnooze(todoId);
  }

  void cancelSnooze(String todoId) {
    _snoozeTimers[todoId]?.cancel();
    _snoozeTimers.remove(todoId);
  }

  void dispose() {
    for (final t in _snoozeTimers.values) { t.cancel(); }
    _snoozeTimers.clear();
    for (final n in _activeNotifications.values) { n.close(); }
    _activeNotifications.clear();
  }

  void showTest() {
    final notification = LocalNotification(
      title: '测试通知',
      body: '这是一条测试通知',
      actions: [
        LocalNotificationAction(text: '完成'),
        LocalNotificationAction(text: '稍后提醒'),
      ],
    );
    notification.onClick = () {
      windowManager.show();
      windowManager.focus();
    };
    notification.onClickAction = (_) {};
    notification.show();
  }
}
