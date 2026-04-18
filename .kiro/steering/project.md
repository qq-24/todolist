# 项目上下文

## 项目结构

```
lib/
  main.dart                    — App 入口，主题配置
  overlay_main.dart            — 悬浮窗独立 FlutterEngine 入口
  config.dart                  — GitHub 配置常量（Token 硬编码）
  models/
    todo.dart                  — Todo 数据模型 + JSON 序列化
  services/
    github_sync_service.dart   — GitHub REST API 交互
    local_storage_service.dart — 本地 JSON 文件读写（原子写入）
    reminder_service.dart      — 跨平台提醒调度（Android MethodChannel + Windows 本地通知）
    windows_notification_service.dart — Windows Toast 通知封装
    windows_tray_service.dart  — Windows 系统托盘管理
  providers/
    todo_provider.dart         — 核心状态管理，CRUD + 同步
    settings_provider.dart     — 主题/排序/开机自启偏好
  screens/
    home_screen.dart           — 主界面
  widgets/
    todo_item.dart             — 任务项（动画 + 滑动删除）
    todo_edit_sheet.dart       — 底部编辑面板
    overlay_reminder.dart      — 悬浮窗 Flutter UI
    sync_icon.dart             — 同步状态图标
    app_drawer.dart            — 侧滑抽屉

android/app/src/main/kotlin/com/mingh/todolist/
  MainActivity.kt              — MethodChannel 桥接 + AlarmHelper + AlarmRescheduleHelper + stableHash
  AlarmReceiver.kt             — 闹钟广播接收器，启动前台 Service
  AlarmForegroundService.kt    — 前台 Service，承载震动/铃声
  AlarmActivity.kt             — 全屏提醒浮窗 Activity
  ReminderOverlay.kt           — FlutterEngine 悬浮窗管理
  TodoAccessibilityService.kt  — 无障碍服务（保活闹钟调度）
```

⚠️ 这是跨平台项目（Android + Windows）。修改提醒、通知、闹钟相关逻辑时，必须同时考虑两端的实现。

## 设计决策

- 状态管理用 provider，不用 Bloc/Riverpod
- 同步用 GitHub REST API Contents 接口，不用 GraphQL
- 本地持久化用 JSON 文件（和远端格式一致），不用 SQLite
- 冲突检测基于 updatedAt 时间戳比对
- 防重复推送用 SHA256 hash 比对（排除 updatedAt 字段）
- 同步防抖 500ms，避免快速连续操作产生多次同步
- _pushLocal 冲突重试最多 2 次
- Todo.copyWith 使用哨兵值模式支持将 deadline 设为 null
- fromJson 全部使用安全解析（tryParse + 默认值），不会因字段缺失崩溃

## 不要动的代码

- config.dart 中的 Token 占位符格式，用户自行替换

## 工作流偏好

- 在 WSL 中编辑代码和打包
- Android 构建后用 adb.exe（不是 adb）安装到设备
- Windows 构建用 cmd.exe /c "cd D:\mingh\Documents\todolist && flutter build windows --release"
- Windows 构建前必须先单独跑 `cmd.exe /c "cd /d D:\mingh\Documents\todolist && dart pub get --no-precompile"`，否则 build 内嵌的 pub get 会因为 WSL→cmd.exe 管道问题卡死
- 项目源码在 /home/mingh/todolist（WSL 侧）和 /mnt/d/mingh/Documents/todolist（Windows 侧映射）

## 开发日志

### 2026-03-25 11:57 通知静默 bug 修复
- 根因：Builder 上的 setVibrate/setSound 在 API 26+ 无效且干扰系统判断 + Channel sound URI 错误 + FSI 被拒绝影响 heads-up
- 修复：参考 Tasks.org，Builder 不设 vibrate/sound/defaults，Channel 用 RingtoneManager 默认铃声，移除 USE_FULL_SCREEN_INTENT
- 新渠道 ID todo_alarm_v4，用 NotificationManagerCompat，notify 加 try-catch
- 已知限制：设备重启后闹钟丢失（无 BOOT_COMPLETED 恢复机制），后续处理
- 同步逻辑从 hash 比对改为"谁新听谁的"（基于 updatedAt 时间戳），参考用户的 Obsidian gitless-sync 插件
- 远端新 → 拉取覆盖本地；本地新 → 推送覆盖远端；一样 → 跳过
- 只有 push 返回 409 时才视为真正并发冲突
- 修复编辑面板底部按钮被系统导航栏挡住的问题（加上 padding.bottom）
- 侧边栏拖拽区域扩大到屏幕左半边
- 删除阈值从 0.5 提高到 0.65，阻尼更明显
- 移除了 dynamic_color 依赖（与 Flutter 3.27 不兼容），改用 ColorScheme.fromSeed
- 从零创建 Flutter 项目，实现全部 8 个 Task
- quick-review 发现并修复了以下问题：
  - Todo.copyWith 无法将 deadline 设为 null → 哨兵值模式
  - fromJson 硬转换可能崩溃 → 安全解析 + 默认值
  - LocalStorageService.load() 只捕获 FormatException → 捕获所有 Exception
  - LocalStorageService.save() 无异常处理 → 添加临时文件清理
  - GithubSyncService.fetch() 无法区分 404 和请求失败 → FetchResult 类型
  - TodoProvider 递归调用风险 → 重试次数上限
  - TodoProvider 竞态条件 → 防抖机制
  - _buildTodoFile() 每次生成新时间戳导致 hash 不稳定 → hash 计算排除 updatedAt
  - HomeScreen.dispose() 中 context.read 不安全 → 缓存 provider 引用
  - 冲突对话框可能重复弹出 → _isConflictDialogShowing 标记
  - TodoEditSheet 保存按钮不随输入更新 → addListener
  - SettingsProvider enum 索引越界 → 边界检查
  - ReminderService 缺少 dispose → 添加 dispose 方法
  - SyncIcon build 中重复控制动画 → 状态变化时才控制

### 2026-03-25 14:50 后台震动不工作 bug 修复
- 现象：应用在前台时震动正常，切到后台/桌面后只有悬浮弹窗没有震动
- 根因：BroadcastReceiver.onReceive() 返回后进程可能被系统回收，导致 Vibrator 和 Handler.postDelayed 的重复震动失效。悬浮窗能存活是因为由系统 WindowManager 管理
- 修复：新增 AlarmForegroundService（前台 Service），AlarmReceiver 不再直接执行震动/铃声，改为启动前台 Service 承载这些操作。前台 Service 有系统级保护不会被轻易回收
- 同时修复：NotificationChannel 未启用震动（版本化渠道重建）、WakeLock 无效 flag 组合（PARTIAL_WAKE_LOCK | ACQUIRE_CAUSES_WAKEUP）、onDestroy 未清理资源
- AndroidManifest.xml 新增 FOREGROUND_SERVICE_SPECIAL_USE 权限和 AlarmForegroundService 注册

### 2026-03-25 14:56 悬浮弹窗优化 + 震动模式 + 滑动删除二次确认
- 悬浮弹窗 UI 重写（方案 D）：四角圆角 28dp、适配系统导航栏高度（底部 padding）、MD3 风格配色（深紫色调）、胶囊形按钮、顶部拖拽指示条
- Todo 模型新增 VibrationMode 枚举（continuous/once），全链路传递：Flutter model → edit sheet → reminder_service → MethodChannel → AlarmHelper → Intent → AlarmReceiver → AlarmForegroundService → ReminderAlert.startVibration(repeat)
- 滑动删除二次确认：第一次滑动弹回并露出 64px 删除条（_deleteArmed 状态），第二次滑动才真正删除。点击删除条图标可取消待删除状态
- quick-review 发现并修复：稍后提醒丢失 vibrationMode、startForeground 失败后未 return、ReminderOverlay.dismiss 使用不同 context 的 WindowManager

### 2026-03-25 15:17 悬浮窗 Flutter 化 + 滑动删除重写
- 悬浮弹窗从原生 Android View 改为独立 FlutterEngine + FlutterView 渲染
  - 新建 lib/overlay_main.dart（@pragma('vm:entry-point') 入口）和 lib/widgets/overlay_reminder.dart（MD3 暗色主题 UI）
  - Kotlin 侧 ReminderOverlay 改为创建 FlutterEngine → FlutterView → WindowManager.addView
  - Dart 主动发 ready 信号解决 isolate 启动竞态问题
  - 添加 eng.lifecycleChannel.appIsResumed() 确保 Flutter 正常渲染
- 滑动删除从 Dismissible + Stack 浮层改为 GestureDetector + AnimationController 单层方案
  - 状态机：idle → armed（左滑超 50px）→ deleting（再左滑超 140px）
  - armed 状态下右滑恢复、点击删除按钮也可删除
  - 全局 ValueNotifier 广播 armed 状态，其他项自动重置
  - _buildContent 背景色改为 scaffoldBackgroundColor 确保内容层不透明
- quick-review 发现并修复：CurvedAnimation 泄漏（死代码）、mounted 守卫、FlutterInjector import 路径

### 2026-03-26 锁屏浮窗修复 + 全流程代码审查
- AlarmActivity 锁屏显示修复（showWhenLocked/turnScreenOn/dismissKeyguard）
- 全流程代码审查发现 8 个问题并修复

### 2026-03-26 Windows 托盘 + 通知 + 开机自启
- 实现 Windows 系统托盘（tray_manager）、Toast 通知（local_notifier）、开机自启（launch_at_startup）
- 窗口管理（window_manager）：关闭缩到托盘、--minimized 启动直接进托盘
- 托盘图标三态（正常/同步中/同步失败）

### 2026-03-27 无障碍服务保活 + 跨端通知
- 新增 TodoAccessibilityService 保活闹钟调度（小米 MIUI 限制下的替代方案）
- Kotlin 端 rescheduleFromLocal 中文 label + stableHash 统一 ID（修复重复通知）
- 浮窗被主界面覆盖 bug：executeAlarm() 的 fullScreenIntent/contentIntent 指向 MainActivity 导致覆盖 AlarmActivity
- 跨端同步关闭通知方案已规划（planner 输出，待执行）
