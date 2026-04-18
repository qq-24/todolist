import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'widgets/overlay_reminder.dart';

/// 悬浮窗专用 Dart 入口，由独立 FlutterEngine 调用
@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.mingh.todolist/overlay');
  bool initialized = false;

  channel.setMethodCallHandler((call) async {
    if (call.method == 'setData' && !initialized) {
      initialized = true;
      final args = call.arguments as Map;
      runApp(OverlayReminderApp(
        message: args['message'] as String? ?? '任务提醒',
        id: args['id'] as int? ?? 0,
        vibrationMode: args['vibrationMode'] as String? ?? 'continuous',
        channel: channel,
      ));
    }
  });

  // 通知原生侧 Dart 已就绪
  channel.invokeMethod('ready');
}
