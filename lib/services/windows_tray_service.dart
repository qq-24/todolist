import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../providers/todo_provider.dart';
import '../providers/settings_provider.dart';

/// Windows 系统托盘服务
class WindowsTrayService with TrayListener {
  final TodoProvider _todoProvider;
  final SettingsProvider _settings;
  SyncStatus _lastStatus = SyncStatus.idle;

  static String _resolveIcon(String name) {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    return '$exeDir\\$name';
  }

  WindowsTrayService(this._todoProvider, this._settings);

  Future<void> init() async {
    trayManager.addListener(this);
    await trayManager.setIcon(_resolveIcon('app_icon.ico'));
    await trayManager.setToolTip('Todo');
    await _updateMenu();
    _todoProvider.addListener(_onSyncStatusChanged);
  }

  void _onSyncStatusChanged() {
    final status = _todoProvider.syncStatus;
    if (status != _lastStatus) {
      _lastStatus = status;
      final icon = switch (status) {
        SyncStatus.syncing => 'app_icon_syncing.ico',
        SyncStatus.error => 'app_icon_error.ico',
        _ => 'app_icon.ico',
      };
      trayManager.setIcon(_resolveIcon(icon));
    }
  }

  Future<void> _updateMenu() async {
    final check = _settings.launchAtStartup ? ' ✓' : '';
    final menu = Menu(items: [
      MenuItem(key: 'show', label: '打开主窗口'),
      MenuItem(key: 'sync', label: '手动同步'),
      MenuItem.separator(),
      MenuItem(key: 'autostart', label: '开机自启$check'),
      MenuItem.separator(),
      MenuItem(key: 'exit', label: '退出'),
    ]);
    await trayManager.setContextMenu(menu);
  }

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() async {
    await _updateMenu();
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'show':
        await windowManager.show();
        await windowManager.focus();
      case 'sync':
        _todoProvider.sync();
      case 'autostart':
        final newVal = !_settings.launchAtStartup;
        await _settings.setLaunchAtStartup(newVal);
        await _updateMenu();
      case 'exit':
        // 先隐藏窗口（视觉上秒关），后台收尾
        try { await windowManager.hide(); } catch (_) {}
        try {
          final pos = await windowManager.getPosition();
          final size = await windowManager.getSize();
          final prefs = await SharedPreferences.getInstance();
          await prefs.setDouble('window_x', pos.dx);
          await prefs.setDouble('window_y', pos.dy);
          await prefs.setDouble('window_w', size.width);
          await prefs.setDouble('window_h', size.height);
        } catch (_) {}
        try { await _todoProvider.sync().timeout(const Duration(seconds: 3)); } catch (_) {}
        try { await trayManager.destroy(); } catch (_) {}
        exit(0);
    }
  }

  void dispose() {
    _todoProvider.removeListener(_onSyncStatusChanged);
    trayManager.removeListener(this);
    trayManager.destroy();
  }
}
