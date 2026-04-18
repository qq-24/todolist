import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../providers/todo_provider.dart';
import '../services/reminder_service.dart';

/// 侧滑抽屉
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final todoProvider = context.watch<TodoProvider>();
    final colorScheme = Theme.of(context).colorScheme;

    // 格式化上次同步时间
    String syncTimeText;
    if (todoProvider.lastSyncTime == null) {
      syncTimeText = '尚未同步';
    } else {
      final t = todoProvider.lastSyncTime!;
      syncTimeText =
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} 已同步';
    }

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            // 标题
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text(
                'Todo 设置',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const Divider(indent: 16, endIndent: 16),

            // ── 同步区域 ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text('同步',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colorScheme.primary)),
            ),
            ListTile(
              leading: const Icon(Icons.sync),
              title: Text(syncTimeText),
              trailing: FilledButton.tonal(
                onPressed: todoProvider.syncStatus == SyncStatus.syncing
                    ? null
                    : () => todoProvider.sync(),
                child: const Text('立即同步'),
              ),
            ),

            const Divider(indent: 16, endIndent: 16),

            // ── 排序方式 ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text('排序方式',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colorScheme.primary)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<SortMode>(
                segments: const [
                  ButtonSegment(
                    value: SortMode.manual,
                    label: Text('手动排序'),
                    icon: Icon(Icons.drag_handle),
                  ),
                  ButtonSegment(
                    value: SortMode.byDeadline,
                    label: Text('按截止时间'),
                    icon: Icon(Icons.schedule),
                  ),
                ],
                selected: {settings.sortMode},
                onSelectionChanged: (v) => settings.setSortMode(v.first),
              ),
            ),

            const Divider(indent: 16, endIndent: 16),

            // ── 主题设置 ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text('主题',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colorScheme.primary)),
            ),

            // 测试通知按钮
            ListTile(
              leading: const Icon(Icons.notifications_active),
              title: const Text('测试通知'),
              subtitle: const Text('5秒后触发强力提醒'),
              onTap: () => ReminderService().testNotification(),
            ),

            // 勿扰震动开关
            SwitchListTile(
              secondary: const Icon(Icons.do_not_disturb),
              title: const Text('勿扰模式时也震动'),
              value: settings.vibrateInDnd,
              onChanged: (v) => settings.setVibrateInDnd(v),
            ),

            const Divider(indent: 16, endIndent: 16),

            RadioListTile<ThemeMode>(
              title: const Text('跟随系统'),
              value: ThemeMode.system,
              groupValue: settings.themeMode,
              onChanged: (v) => settings.setThemeMode(v!),
            ),
            RadioListTile<ThemeMode>(
              title: const Text('浅色'),
              value: ThemeMode.light,
              groupValue: settings.themeMode,
              onChanged: (v) => settings.setThemeMode(v!),
            ),
            RadioListTile<ThemeMode>(
              title: const Text('深色'),
              value: ThemeMode.dark,
              groupValue: settings.themeMode,
              onChanged: (v) => settings.setThemeMode(v!),
            ),
          ],
        ),
      ),
    );
  }
}
