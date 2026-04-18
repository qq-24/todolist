# Windows 托盘常驻 + 系统通知 + 开机自启

## Requirements

### R1: 系统托盘常驻
- 描述：关闭主窗口时隐藏到系统托盘继续运行，托盘图标随同步状态变化（三态），支持右键菜单
- 验收标准：
  - [ ] 关闭主窗口后应用不退出，托盘图标可见
  - [ ] 首次关闭弹提示"已最小化到系统托盘"，可勾"不再提示"
  - [ ] 左键单击托盘图标打开/聚焦主窗口
  - [ ] 右键菜单：打开主窗口 / 手动同步 / 分隔线 / 开机自启 ✓ / 分隔线 / 退出
  - [ ] 托盘图标三态：正常 / 同步中（蓝色） / 同步失败（红色）

### R2: Win11 Toast 通知
- 描述：任务到期时通过 Windows 原生 Toast 通知提醒，支持"完成"和"稍后提醒"操作按钮
- 验收标准：
  - [ ] 任务到期时弹出 Win11 Toast 通知（标题+内容）
  - [ ] 通知上"完成"按钮能标记任务完成
  - [ ] 通知上"稍后提醒"按钮 15 分钟后再次通知
  - [ ] 点击通知本体打开主窗口并聚焦到对应任务
  - [ ] Windows 测试通知按钮可用

### R3: 开机自启
- 描述：通过注册表实现便携版开机自启，启动后直接进托盘不弹窗口
- 验收标准：
  - [ ] 侧边栏"开机自启"开关可切换（仅 Windows 显示）
  - [ ] 默认开启
  - [ ] 开机自启后应用自动进托盘不弹窗
  - [ ] exe 路径变更后启动时自动更新注册表

## Technical Design

### 架构概览

```
main.dart
  ├─ 检测 --minimized 参数
  ├─ 初始化 windowManager（setPreventClose）
  ├─ 初始化 WindowsTrayService（托盘图标+菜单）
  ├─ 初始化 local_notifier
  └─ 监听 TodoProvider.syncStatus → 更新托盘图标

WindowsTrayService (新建)
  ├─ 托盘图标管理（三态切换）
  ├─ 右键菜单构建与事件处理
  └─ 左键点击 → windowManager.show()/focus()

ReminderService (修改)
  └─ Windows Timer 回调 → LocalNotification.show()
      ├─ onClick → 打开窗口 + 聚焦任务
      ├─ onClickAction(0) → toggleComplete
      └─ onClickAction(1) → 15分钟后重新调度

SettingsProvider (修改)
  └─ launchAtStartup bool 字段 + getter/setter

HomeScreen (修改)
  └─ onWindowClose → 首次弹提示 → windowManager.hide()
```

### 新增依赖

```yaml
# pubspec.yaml dependencies 新增
tray_manager: ^0.5.2
local_notifier: ^0.1.6
launch_at_startup: ^0.5.1
window_manager: ^0.5.1
```

### 新增资产文件

需要 3 个 .ico 文件用于托盘三态图标：
- `windows/runner/resources/app_icon.ico` — 已有，正常态（需替换为自定义图标）
- `windows/runner/resources/app_icon_syncing.ico` — 新建，同步中态（蓝色叠加）
- `windows/runner/resources/app_icon_error.ico` — 新建，同步失败态（红色叠加）

同时用 Android 的 icon 生成 Windows .ico 替换默认图标。

### 详细设计

---

#### 文件：pubspec.yaml（修改）

```diff
 dependencies:
   flutter:
     sdk: flutter
   flutter_localizations:
     sdk: flutter
   http: ^1.2.0
   path_provider: ^2.1.0
   shared_preferences: ^2.2.0
   provider: ^6.1.0
   uuid: ^4.2.0
   crypto: ^3.0.0
+  tray_manager: ^0.5.2
+  local_notifier: ^0.1.6
+  launch_at_startup: ^0.5.1
+  window_manager: ^0.5.1
```

---

#### 文件：lib/services/windows_tray_service.dart（新建）

职责：管理系统托盘图标、菜单、事件

```dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../providers/todo_provider.dart';
import '../providers/settings_provider.dart';

class WindowsTrayService with TrayListener {
  final TodoProvider _todoProvider;
  final SettingsProvider _settings;
  SyncStatus _lastStatus = SyncStatus.idle;

  // .ico 文件路径（相对于 exe 目录）
  static String get _iconNormal => _resolveIcon('app_icon.ico');
  static String get _iconSyncing => _resolveIcon('app_icon_syncing.ico');
  static String get _iconError => _resolveIcon('app_icon_error.ico');

  static String _resolveIcon(String name) {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    return '$exeDir\\$name';
  }

  WindowsTrayService(this._todoProvider, this._settings);

  Future<void> init() async {
    trayManager.addListener(this);
    await trayManager.setIcon(_iconNormal);
    await trayManager.setToolTip('Todo');
    await _updateMenu();
    _todoProvider.addListener(_onSyncStatusChanged);
  }

  void _onSyncStatusChanged() {
    final status = _todoProvider.syncStatus;
    if (status != _lastStatus) {
      _lastStatus = status;
      _updateIcon(status);
    }
  }

  Future<void> _updateIcon(SyncStatus status) async {
    final icon = switch (status) {
      SyncStatus.syncing => _iconSyncing,
      SyncStatus.error => _iconError,
      _ => _iconNormal,
    };
    await trayManager.setIcon(icon);
  }

  Future<void> _updateMenu() async {
    final isAutoStart = _settings.launchAtStartup;
    final menu = Menu(items: [
      MenuItem(key: 'show', label: '打开主窗口'),
      MenuItem(key: 'sync', label: '手动同步'),
      MenuItem.separator(),
      MenuItem(key: 'autostart', label: '开机自启 ${isAutoStart ? "✓" : ""}'),
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
  void onTrayIconRightMouseDown() {
    _updateMenu(); // 刷新菜单状态
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
        // 真正退出
        await trayManager.destroy();
        exit(0);
    }
  }

  void dispose() {
    _todoProvider.removeListener(_onSyncStatusChanged);
    trayManager.removeListener(this);
    trayManager.destroy();
  }
}
```

---

#### 文件：lib/services/windows_notification_service.dart（新建）

职责：Windows Toast 通知发送、按钮回调处理

```dart
import 'dart:async';

import 'package:local_notifier/local_notifier.dart';

import '../models/todo.dart';
import '../providers/todo_provider.dart';

/// 通知点击时需要聚焦的任务 ID
final focusTodoNotifier = ValueNotifier<String?>(null);
// 需要 import 'package:flutter/foundation.dart'; 在使用处

class WindowsNotificationService {
  final TodoProvider _todoProvider;

  WindowsNotificationService(this._todoProvider);

  Future<void> init() async {
    await localNotifier.setup(
      appName: 'Todo',
      shortcutPolicy: ShortcutPolicy.requireCreate,
    );
  }

  void showReminder(Todo todo, String message) {
    final notification = LocalNotification(
      title: '任务提醒',
      body: message,
      actions: [
        LocalNotificationAction(text: '完成'),
        LocalNotificationAction(text: '稍后提醒'),
      ],
    );

    notification.onClick = () {
      // 点击通知本体 → 打开窗口聚焦任务
      focusTodoNotifier.value = todo.id;
    };

    notification.onClickAction = (actionIndex) {
      if (actionIndex == 0) {
        // "完成"
        _todoProvider.toggleComplete(todo.id);
      } else if (actionIndex == 1) {
        // "稍后提醒" → 15分钟后重新通知
        Timer(const Duration(minutes: 15), () {
          showReminder(todo, '稍后提醒: ${todo.title}');
        });
      }
    };

    notification.show();
  }

  void showTest() {
    final notification = LocalNotification(
      title: '测试通知',
      body: '这是一条测试通知，5秒后触发',
      actions: [
        LocalNotificationAction(text: '完成'),
        LocalNotificationAction(text: '稍后提醒'),
      ],
    );
    notification.onClick = () {};
    notification.onClickAction = (i) {};
    notification.show();
  }
}
```

---

#### 文件：lib/services/reminder_service.dart（修改）

```diff
 import 'dart:async';
 import 'dart:io';

 import 'package:flutter/foundation.dart';
 import 'package:flutter/services.dart';

 import '../models/todo.dart';
+import 'windows_notification_service.dart';

 class ReminderService {
   static const _channel = MethodChannel('com.mingh.todolist/alarm');
   final Map<String, Timer> _timers = {};
+  WindowsNotificationService? _winNotifier;
+
+  void setWindowsNotifier(WindowsNotificationService notifier) {
+    _winNotifier = notifier;
+  }

   Future<void> scheduleReminder(Todo todo) async {
     // ... 不变 ...

       } else if (Platform.isWindows) {
         final delay = time.difference(DateTime.now());
         final timerKey = '${todo.id}_${advance.name}';
         _timers[timerKey] = Timer(delay, () {
-          debugPrint('⏰ 任务提醒: $message');
+          _winNotifier?.showReminder(todo, message);
         });
       }
     }
   }

   Future<void> testNotification() async {
     if (Platform.isAndroid) {
       try {
         await _channel.invokeMethod('testNotification');
       } on PlatformException catch (e) {
         debugPrint('测试通知失败: $e');
       }
+    } else if (Platform.isWindows) {
+      _winNotifier?.showTest();
     }
   }
```

---

#### 文件：lib/providers/settings_provider.dart（修改）

```diff
+import 'dart:io';
+
+import 'package:launch_at_startup/launch_at_startup.dart';

 class SettingsProvider extends ChangeNotifier {
   ThemeMode _themeMode = ThemeMode.system;
   SortMode _sortMode = SortMode.manual;
   bool _vibrateInDnd = true;
+  bool _launchAtStartup = true;

   // ... 现有 getter ...
+  bool get launchAtStartup => _launchAtStartup;

   Future<void> init() async {
     final prefs = await SharedPreferences.getInstance();
     // ... 现有加载 ...
+    _launchAtStartup = prefs.getBool('launch_at_startup') ?? true;
+
+    // Windows: 初始化 launch_at_startup 并同步状态
+    if (Platform.isWindows) {
+      launchAtStartup.setup(
+        appName: 'todolist',
+        appPath: Platform.resolvedExecutable,
+        args: ['--minimized'],
+      );
+      // 同步注册表状态（处理 exe 路径变更）
+      if (_launchAtStartup) {
+        await launchAtStartup.enable();
+      } else {
+        await launchAtStartup.disable();
+      }
+    }
     notifyListeners();
   }

+  Future<void> setLaunchAtStartup(bool value) async {
+    _launchAtStartup = value;
+    notifyListeners();
+    final prefs = await SharedPreferences.getInstance();
+    await prefs.setBool('launch_at_startup', value);
+    if (Platform.isWindows) {
+      if (value) {
+        await launchAtStartup.enable();
+      } else {
+        await launchAtStartup.disable();
+      }
+    }
+  }
```

---

#### 文件：lib/main.dart（修改）

```diff
+import 'dart:io';
+
 import 'package:flutter/material.dart';
 import 'package:flutter_localizations/flutter_localizations.dart';
 import 'package:provider/provider.dart';
+import 'package:window_manager/window_manager.dart';

 import 'providers/settings_provider.dart';
 import 'providers/todo_provider.dart';
 import 'screens/home_screen.dart';
+import 'services/windows_tray_service.dart';
+import 'services/windows_notification_service.dart';

 void main() async {
   WidgetsFlutterBinding.ensureInitialized();

   final settings = SettingsProvider();
   await settings.init();

   final todoProvider = TodoProvider(settings);

+  // Windows: 窗口管理 + 托盘 + 通知
+  WindowsTrayService? trayService;
+  if (Platform.isWindows) {
+    await windowManager.ensureInitialized();
+    await windowManager.setPreventClose(true);
+
+    final startMinimized = Platform.executableArguments.contains('--minimized');
+    if (startMinimized) {
+      await windowManager.hide();
+    }
+
+    // 通知服务
+    final winNotifier = WindowsNotificationService(todoProvider);
+    await winNotifier.init();
+    todoProvider.reminder.setWindowsNotifier(winNotifier);
+
+    // 托盘服务
+    trayService = WindowsTrayService(todoProvider, settings);
+    await trayService.init();
+  }

   runApp(
     MultiProvider(
       providers: [
         ChangeNotifierProvider.value(value: settings),
         ChangeNotifierProvider.value(value: todoProvider),
       ],
       child: const TodoApp(),
     ),
   );

   todoProvider.init();
 }
```

注意：需要在 TodoProvider 中暴露 `reminder` getter：

```diff
 // todo_provider.dart
 class TodoProvider extends ChangeNotifier {
   final _reminder = ReminderService();
+  ReminderService get reminder => _reminder;
```

---

#### 文件：lib/screens/home_screen.dart（修改）

```diff
+import 'package:window_manager/window_manager.dart';
+import '../services/windows_notification_service.dart';

-class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
+class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver, WindowListener {
   // ... 现有字段 ...
+  bool _trayHintShown = false;

   @override
   void initState() {
     super.initState();
     WidgetsBinding.instance.addObserver(this);
     _provider = context.read<TodoProvider>();
     _provider.addListener(_onProviderChanged);
+    if (_isDesktop) {
+      windowManager.addListener(this);
+      _loadTrayHintPref();
+      // 监听通知点击聚焦任务
+      focusTodoNotifier.addListener(_onFocusTodo);
+    }
   }

+  Future<void> _loadTrayHintPref() async {
+    final prefs = await SharedPreferences.getInstance();
+    _trayHintShown = prefs.getBool('tray_hint_shown') ?? false;
+  }

   @override
   void dispose() {
     WidgetsBinding.instance.removeObserver(this);
     _provider.removeListener(_onProviderChanged);
+    if (_isDesktop) {
+      windowManager.removeListener(this);
+      focusTodoNotifier.removeListener(_onFocusTodo);
+    }
     super.dispose();
   }

+  void _onFocusTodo() {
+    final todoId = focusTodoNotifier.value;
+    if (todoId == null) return;
+    focusTodoNotifier.value = null;
+    // 打开窗口
+    windowManager.show();
+    windowManager.focus();
+    // 找到任务并打开编辑面板
+    final todos = _provider.sortedTodos;
+    final index = todos.indexWhere((t) => t.id == todoId);
+    if (index != -1) {
+      showTodoEditSheet(context, todo: todos[index]);
+    }
+  }

+  @override
+  void onWindowClose() async {
+    if (!_trayHintShown) {
+      _trayHintShown = true;
+      final prefs = await SharedPreferences.getInstance();
+      await prefs.setBool('tray_hint_shown', true);
+      if (mounted) {
+        await showDialog(
+          context: context,
+          builder: (ctx) => AlertDialog(
+            title: const Text('最小化到托盘'),
+            content: const Text('应用已最小化到系统托盘，可从托盘图标重新打开。'),
+            actions: [
+              FilledButton(
+                onPressed: () => Navigator.of(ctx).pop(),
+                child: const Text('知道了'),
+              ),
+            ],
+          ),
+        );
+      }
+    }
+    await windowManager.hide();
+  }
```

---

#### 文件：lib/widgets/app_drawer.dart（修改）

```diff
             // 测试通知（仅 Android）
-            if (Platform.isAndroid)
+            if (Platform.isAndroid || Platform.isWindows)
               ListTile(
                 leading: const Icon(Icons.notifications_active),
                 title: const Text('测试通知'),
                 subtitle: const Text('5秒后触发强力提醒'),
                 onTap: () => ReminderService().testNotification(),
               ),

+            // 开机自启（仅 Windows）
+            if (Platform.isWindows)
+              SwitchListTile(
+                secondary: const Icon(Icons.power_settings_new),
+                title: const Text('开机自启'),
+                value: settings.launchAtStartup,
+                onChanged: (v) => settings.setLaunchAtStartup(v),
+              ),
```

注意：app_drawer 中的测试通知 `ReminderService().testNotification()` 创建了新实例，
Windows 上新实例没有 `_winNotifier`。需要改为从 Provider 获取：

```diff
-                onTap: () => ReminderService().testNotification(),
+                onTap: () => context.read<TodoProvider>().reminder.testNotification(),
```

---

#### 文件：windows/runner/resources/（图标文件）

需要生成 3 个 .ico 文件：
- 从 `assets/icon.png`（或 Android 的 xxxhdpi ic_launcher.png）生成 `app_icon.ico`（替换默认）
- 生成蓝色叠加版 `app_icon_syncing.ico`
- 生成红色叠加版 `app_icon_error.ico`

图标生成方式：用 ImageMagick 或 Python Pillow 从 PNG 转换。

---

### 影响评估

- `todo_provider.dart` — 仅新增一个 getter，无破坏性变更
- `reminder_service.dart` — Windows 分支行为变更（debugPrint → 真实通知），Android 不受影响
- `settings_provider.dart` — 新增字段，init() 中新增 Windows 分支，不影响 Android
- `main.dart` — 启动流程新增 Windows 分支，Android 不受影响
- `home_screen.dart` — 新增 WindowListener mixin，仅 Windows 生效
- `app_drawer.dart` — 新增 Windows 专属 UI 项

## Tasks

### Task 1: 新增依赖 + 图标文件
- [x] 目标：添加 4 个包依赖，生成并替换图标文件
- 涉及文件：
  - `pubspec.yaml`
  - `windows/runner/resources/app_icon.ico`（替换）
  - `windows/runner/resources/app_icon_syncing.ico`（新建）
  - `windows/runner/resources/app_icon_error.ico`（新建）
- 验证方式：`flutter pub get` 成功，图标文件存在

### Task 2: 新建 WindowsNotificationService
- [x] 目标：封装 Win11 Toast 通知，支持操作按钮回调
- 涉及文件：
  - `lib/services/windows_notification_service.dart`（新建）
- 前置依赖：Task 1
- 验证方式：调用 showTest() 能弹出 Toast 通知

### Task 3: 修改 ReminderService 集成 Windows 通知
- [x] 目标：Windows Timer 回调改为发送真实通知，测试通知支持 Windows
- 涉及文件：
  - `lib/services/reminder_service.dart`
- 前置依赖：Task 2
- 验证方式：Windows 上任务到期弹出 Toast 通知

### Task 4: 新建 WindowsTrayService
- [x] 目标：系统托盘图标+菜单+事件处理+三态图标
- 涉及文件：
  - `lib/services/windows_tray_service.dart`（新建）
- 前置依赖：Task 1
- 验证方式：托盘图标可见，右键菜单功能正常，同步状态变化时图标切换

### Task 5: 修改 SettingsProvider 支持开机自启
- [x] 目标：新增 launchAtStartup 设置项，注册表管理
- 涉及文件：
  - `lib/providers/settings_provider.dart`
- 前置依赖：Task 1
- 验证方式：设置开关后注册表正确写入/删除，exe 路径变更后自动更新

### Task 6: 修改 TodoProvider 暴露 reminder
- [x] 目标：暴露 ReminderService 实例供外部注入 Windows 通知服务
- 涉及文件：
  - `lib/providers/todo_provider.dart`
- 前置依赖：无
- 验证方式：`todoProvider.reminder` 可访问

### Task 7: 修改 main.dart 集成启动流程
- [x] 目标：Windows 启动时初始化窗口管理、托盘、通知，支持 --minimized 参数
- 涉及文件：
  - `lib/main.dart`
- 前置依赖：Task 2, 3, 4, 5, 6
- 验证方式：正常启动弹窗口+托盘；--minimized 启动只有托盘

### Task 8: 修改 HomeScreen 拦截关闭 + 通知聚焦
- [x] 目标：关闭按钮缩到托盘（首次有提示），通知点击聚焦任务
- 涉及文件：
  - `lib/screens/home_screen.dart`
- 前置依赖：Task 7
- 验证方式：关闭窗口缩到托盘，首次有提示；点击通知打开窗口并聚焦任务

### Task 9: 修改 AppDrawer 新增设置项
- [x] 目标：侧边栏新增"开机自启"开关（仅 Windows），测试通知支持 Windows
- 涉及文件：
  - `lib/widgets/app_drawer.dart`
- 前置依赖：Task 5, 6
- 验证方式：Windows 侧边栏显示开机自启开关和测试通知按钮
