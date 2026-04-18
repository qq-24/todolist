import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 悬浮窗提醒 UI（独立 FlutterEngine 渲染）
class OverlayReminderApp extends StatelessWidget {
  final String message;
  final int id;
  final String vibrationMode;
  final MethodChannel channel;

  const OverlayReminderApp({
    super.key,
    required this.message,
    required this.id,
    required this.vibrationMode,
    required this.channel,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: _OverlayPage(
        message: message,
        channel: channel,
      ),
    );
  }
}

class _OverlayPage extends StatelessWidget {
  final String message;
  final MethodChannel channel;

  const _OverlayPage({required this.message, required this.channel});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // 解析任务内容（去掉"到期时: "等前缀）
    final parts = message.split(': ');
    final content = parts.length > 1 ? parts.sublist(1).join(': ') : message;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          const Spacer(),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: EdgeInsets.only(
              left: 24, right: 24, top: 20,
              bottom: 20 + MediaQuery.of(context).padding.bottom,
            ),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 拖拽指示条
                Center(
                  child: Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // 标题行
                Row(
                  children: [
                    Text('⏰', style: TextStyle(fontSize: 22)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('任务提醒',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: colorScheme.onSurfaceVariant),
                      onPressed: () => channel.invokeMethod('dismiss'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // 任务内容
                Text(content,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 24),
                // 按钮行
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => channel.invokeMethod('snooze'),
                        child: const Text('稍后提醒'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => channel.invokeMethod('dismiss'),
                        child: const Text('知道了'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
