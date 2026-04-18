import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../providers/todo_provider.dart';
import '../screens/done_collection_screen.dart';
import '../services/hotkey_service.dart';

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
    final isError = todoProvider.syncStatus == SyncStatus.error;
    if (isError) {
      syncTimeText = '同步失败${todoProvider.lastError != null ? '：${todoProvider.lastError}' : ''}';
    } else if (todoProvider.lastSyncTime == null) {
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
              title: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(syncTimeText, style: isError ? TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13) : null),
              ),
              trailing: FilledButton.tonal(
                onPressed: todoProvider.syncStatus == SyncStatus.syncing
                    ? null
                    : () => todoProvider.sync(),
                child: const Text('立即同步'),
              ),
            ),

            ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: const Text('做过的 · 合集'),
              trailing: Text(
                '${todoProvider.completedWishes.length}',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DoneCollectionScreen()),
                );
              },
            ),

            ListTile(
              leading: const Icon(Icons.cloud_sync),
              title: const Text('GitHub 同步配置'),
              subtitle: Text(settings.isGithubConfigured ? '已配置' : '未配置',
                style: TextStyle(color: settings.isGithubConfigured ? null : colorScheme.error)),
              onTap: () => _showGithubConfigDialog(context, settings),
            ),

            const Divider(indent: 16, endIndent: 16),

            // ── 排序方式 ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text('排序方式',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colorScheme.primary)),
            ),
            RadioListTile<SortMode>(
              title: const Text('手动排序'),
              value: SortMode.manual,
              groupValue: settings.sortMode,
              onChanged: (v) => settings.setSortMode(v!),
              dense: true,
            ),
            RadioListTile<SortMode>(
              title: const Text('按截止时间'),
              value: SortMode.byDeadline,
              groupValue: settings.sortMode,
              onChanged: (v) => settings.setSortMode(v!),
              dense: true,
            ),
            RadioListTile<SortMode>(
              title: const Text('按添加时间'),
              value: SortMode.byCreatedTime,
              groupValue: settings.sortMode,
              onChanged: (v) => settings.setSortMode(v!),
              dense: true,
            ),

            const Divider(indent: 16, endIndent: 16),

            // ── 主题设置 ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text('主题',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colorScheme.primary)),
            ),

            // 勿扰震动开关
            SwitchListTile(
              secondary: const Icon(Icons.do_not_disturb),
              title: const Text('勿扰模式时也震动'),
              value: settings.vibrateInDnd,
              onChanged: (v) => settings.setVibrateInDnd(v),
            ),

            const Divider(indent: 16, endIndent: 16),

            // 测试通知（Android 和 Windows）
            if (Platform.isAndroid || Platform.isWindows)
              ListTile(
                leading: const Icon(Icons.notifications_active),
                title: const Text('测试通知'),
                subtitle: const Text('5秒后触发强力提醒'),
                onTap: () => context.read<TodoProvider>().reminder.testNotification(),
              ),

            // 开机自启（仅 Windows）
            if (Platform.isWindows)
              SwitchListTile(
                secondary: const Icon(Icons.power_settings_new),
                title: const Text('开机自启'),
                value: settings.launchAtStartup,
                onChanged: (v) => settings.setLaunchAtStartup(v),
              ),

            // 全局快捷键（仅 Windows）
            if (Platform.isWindows)
              ListTile(
                leading: const Icon(Icons.keyboard),
                title: const Text('全局快捷键'),
                trailing: Text(
                  HotkeyService.formatForDisplay(settings.hotkey),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.primary,
                  ),
                ),
                onTap: () => _showHotkeyRecorder(context, settings),
              ),

            // 新建任务快捷键（仅桌面端）
            if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
              ListTile(
                leading: const Icon(Icons.add_circle_outline),
                title: const Text('新建任务快捷键'),
                trailing: DropdownButton<String>(
                  value: settings.addTaskKey,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 'space', child: Text('空格')),
                    DropdownMenuItem(value: 'enter', child: Text('Enter')),
                  ],
                  onChanged: (v) { if (v != null) settings.setAddTaskKey(v); },
                ),
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

void _showHotkeyRecorder(BuildContext context, SettingsProvider settings) {
  final currentHotKey = HotkeyService.parseHotkey(settings.hotkey);
  showDialog(
    context: context,
    builder: (ctx) {
      String? errorText;
      return StatefulBuilder(builder: (ctx, setDialogState) => AlertDialog(
        title: const Text('设置快捷键'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('请按下新的快捷键组合\n（仅支持 字母/数字 + 修饰键）', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            HotKeyRecorder(
              initalHotKey: currentHotKey,
              onHotKeyRecorded: (hotKey) {
                final str = HotkeyService.hotkeyToString(hotKey);
                if (str == null) {
                  setDialogState(() => errorText = '不支持该按键，请使用字母或数字键');
                  return;
                }
                settings.setHotkey(str);
                Navigator.of(ctx).pop();
              },
            ),
            if (errorText != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(errorText!, style: TextStyle(color: Theme.of(ctx).colorScheme.error, fontSize: 13)),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              settings.setHotkey('alt+t');
              Navigator.of(ctx).pop();
            },
            child: const Text('恢复默认'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
        ],
      ));
    },
  );
}

void _showGithubConfigDialog(BuildContext context, SettingsProvider settings) {
  final tokenCtrl = TextEditingController(text: settings.githubToken);
  final ownerCtrl = TextEditingController(text: settings.githubOwner);
  final repoCtrl = TextEditingController(text: settings.githubRepo);

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('GitHub 同步配置'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: tokenCtrl, decoration: const InputDecoration(labelText: 'Personal Access Token', border: OutlineInputBorder()), obscureText: true),
          const SizedBox(height: 12),
          TextField(controller: ownerCtrl, decoration: const InputDecoration(labelText: 'Owner (用户名)', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: repoCtrl, decoration: const InputDecoration(labelText: 'Repo (仓库名)', border: OutlineInputBorder())),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(
          onPressed: () async {
            await settings.setGithubConfig(
              token: tokenCtrl.text.trim(),
              owner: ownerCtrl.text.trim(),
              repo: repoCtrl.text.trim(),
            );
            if (ctx.mounted) Navigator.pop(ctx);
            if (settings.isGithubConfigured) {
              context.read<TodoProvider>().sync();
            }
          },
          child: const Text('保存'),
        ),
      ],
    ),
  );
}
