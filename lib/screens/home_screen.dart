import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../models/todo.dart';
import '../providers/todo_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/app_drawer.dart';
import '../widgets/sync_icon.dart';
import '../widgets/todo_edit_sheet.dart';
import '../widgets/todo_item.dart';
import '../services/windows_notification_service.dart';

/// 主界面
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver, WindowListener {
  late final TodoProvider _provider;
  bool _isConflictDialogShowing = false;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  static final _isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  bool _trayHintShown = false;
  bool _isHiding = false;
  Timer? _drawerAutoCloseTimer;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _provider = context.read<TodoProvider>();
    _provider.addListener(_onProviderChanged);
    if (Platform.isWindows) {
      windowManager.addListener(this);
      _loadTrayHintPref();
      focusTodoNotifier.addListener(_onFocusTodo);
    }
    if (Platform.isAndroid) {
      _checkAccessibility();
    }
  }

  @override
  void dispose() {
    _drawerAutoCloseTimer?.cancel();
    _focusNode.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _provider.removeListener(_onProviderChanged);
    if (Platform.isWindows) {
      windowManager.removeListener(this);
      focusTodoNotifier.removeListener(_onFocusTodo);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _provider.resumePolling();
      _provider.processPendingActions();
    } else if (state == AppLifecycleState.paused) {
      _provider.pausePolling();
    }
  }

  void _onProviderChanged() {
    if (!mounted) return;
    if (_provider.hasConflict && !_isConflictDialogShowing) {
      _showConflictDialog();
    }
  }

  Future<void> _loadTrayHintPref() async {
    final prefs = await SharedPreferences.getInstance();
    _trayHintShown = prefs.getBool('tray_hint_shown') ?? false;
  }

  Future<void> _checkAccessibility() async {
    try {
      const channel = MethodChannel('com.mingh.todolist/alarm');
      final enabled = await channel.invokeMethod<bool>('checkAccessibility') ?? false;
      if (!enabled && mounted) {
        final prefs = await SharedPreferences.getInstance();
        final dismissed = prefs.getBool('accessibility_hint_dismissed') ?? false;
        if (dismissed) return;
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('开启提醒保活'),
            content: const Text('为确保应用被关闭后提醒仍能正常触发，请在无障碍设置中开启 Todo 服务。'),
            actions: [
              TextButton(
                onPressed: () async {
                  await prefs.setBool('accessibility_hint_dismissed', true);
                  Navigator.of(ctx).pop();
                },
                child: const Text('不再提示'),
              ),
              FilledButton(
                onPressed: () async {
                  await channel.invokeMethod('openAccessibilitySettings');
                  Navigator.of(ctx).pop();
                },
                child: const Text('去开启'),
              ),
            ],
          ),
        );
      }
    } catch (_) {
      // MethodChannel 通信失败时静默忽略
    }
  }

  void _onFocusTodo() {
    final todoId = focusTodoNotifier.value;
    if (todoId == null) return;
    focusTodoNotifier.value = null;
    final todos = _provider.sortedTodos;
    final index = todos.indexWhere((t) => t.id == todoId);
    if (index != -1) {
      showTodoEditSheet(context, todo: todos[index]);
    }
  }

  @override
  void onWindowFocus() {
    // 窗口获得焦点时同步（节流：距上次同步不足 10 秒则跳过）
    final last = _provider.lastSyncTime;
    if (last != null && DateTime.now().difference(last).inSeconds < 10) return;
    _provider.sync();
  }

  @override
  void onWindowClose() async {
    if (_isHiding) return;
    _isHiding = true;
    try {
      // 保存窗口位置和大小
      final pos = await windowManager.getPosition();
      final size = await windowManager.getSize();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('window_x', pos.dx);
      await prefs.setDouble('window_y', pos.dy);
      await prefs.setDouble('window_w', size.width);
      await prefs.setDouble('window_h', size.height);
      if (!_trayHintShown) {
        _trayHintShown = true;
        await prefs.setBool('tray_hint_shown', true);
        if (mounted) {
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('最小化到托盘'),
              content: const Text('应用已最小化到系统托盘，可从托盘图标重新打开。'),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('知道了'),
                ),
              ],
            ),
          );
        }
      }
      await windowManager.hide();
    } finally {
      _isHiding = false;
    }
  }

  void _showConflictDialog() {
    _isConflictDialogShowing = true;
    final localCount = _provider.sortedTodos.length;
    final remoteData = _provider.conflictRemoteData;
    final remoteCount = remoteData?.todos.length ?? 0;
    final localTime = _provider.lastSyncTime;
    final remoteTime = remoteData?.updatedAt;

    String info = '本地 $localCount 条，远端 $remoteCount 条。';
    if (localTime != null) info += '\n本地最后修改: ${_fmtTime(localTime)}';
    if (remoteTime != null) info += '\n远端最后修改: ${_fmtTime(remoteTime)}';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        String? errorMsg;
        return StatefulBuilder(builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('同步冲突'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(info),
            if (errorMsg != null) Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(errorMsg!, style: TextStyle(color: Theme.of(ctx).colorScheme.error, fontSize: 13)),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () async {
                await _provider.resolveConflict(false);
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child: const Text('保留远端'),
            ),
            FilledButton(
              onPressed: () async {
                final ok = await _provider.resolveConflict(true);
                if (ok) {
                  if (ctx.mounted) Navigator.of(ctx).pop();
                } else {
                  setDialogState(() => errorMsg = '推送失败，请重试');
                }
              },
              child: const Text('保留本地'),
            ),
          ],
        ));
      },
    ).then((_) => _isConflictDialogShowing = false);
  }

  String _fmtTime(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  void _startDrawerAutoClose() {
    _drawerAutoCloseTimer = Timer(const Duration(milliseconds: 300), () {
      _drawerAutoCloseTimer = null;
      if (mounted
          && _scaffoldKey.currentState?.isDrawerOpen == true
          && ModalRoute.of(this.context)?.isCurrent == true) {
        _scaffoldKey.currentState!.closeDrawer();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TodoProvider>();
    final todos = provider.sortedTodos;
    final isWish = provider.currentKind == TodoKind.wish;

    return ValueListenableBuilder<String?>(
      valueListenable: armedNotifier,
      builder: (context, armedId, _) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final scaffold = Theme(
        data: Theme.of(context).copyWith(
          scaffoldBackgroundColor: isWish
              ? (isDark ? const Color(0xFF1A1714) : const Color(0xFFFAF5EE))
              : null,
        ),
        child: Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(
          isWish ? '想做的' : 'Todo',
          style: isWish ? GoogleFonts.notoSerifSc() : null,
        ),
        actions: const [SyncIcon()],
      ),
      drawer: const AppDrawer(),
      drawerEdgeDragWidth: armedId != null ? 0 : MediaQuery.of(context).size.width * 0.5,
      body: GestureDetector(
        onTap: () => armedNotifier.value = null,
        behavior: HitTestBehavior.translucent,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SegmentedButton<TodoKind>(
              multiSelectionEnabled: false,
              emptySelectionAllowed: false,
              selected: {provider.currentKind},
              onSelectionChanged: (s) => provider.setKind(s.first),
              segments: [
                ButtonSegment(
                  value: TodoKind.task,
                  icon: const Icon(Icons.checklist),
                  label: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Text('要做的'),
                    const SizedBox(width: 4),
                    Text('${provider.countByKind(TodoKind.task)}',
                        style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5))),
                  ]),
                ),
                ButtonSegment(
                  value: TodoKind.wish,
                  icon: const Icon(Icons.auto_awesome),
                  label: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Text('想做的'),
                    const SizedBox(width: 4),
                    Text('${provider.countByKind(TodoKind.wish)}',
                        style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5))),
                  ]),
                ),
              ],
            ),
          ),
          Expanded(child: todos.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(isWish ? Icons.auto_awesome : Icons.check_circle_outline,
                      size: 64,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.2)),
                  const SizedBox(height: 16),
                  Text(
                    isWish ? '点击 + 记下想做的事' : '点击 + 添加第一个任务',
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            )
          : NotificationListener<ScrollNotification>(
              onNotification: (_) { armedNotifier.value = null; return false; },
              child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom + 80,
              ),
              itemCount: todos.length,
              onReorder: provider.reorder,
              proxyDecorator: (child, index, animation) {
                return AnimatedBuilder(
                  animation: animation,
                  builder: (context, child) => Material(
                    elevation: 2,
                    shadowColor: Theme.of(context)
                        .colorScheme
                        .shadow
                        .withValues(alpha: 0.3),
                    child: child,
                  ),
                  child: child,
                );
              },
              itemBuilder: (context, index) {
                final todo = todos[index];
                return TodoItem(key: ValueKey(todo.id), todo: todo, index: index);
              },
            )),
      ),
        ]),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showTodoEditSheet(context),
        child: const Icon(Icons.add),
      ),
    ));
      if (!_isDesktop) return scaffold;
      final addTaskKey = context.watch<SettingsProvider>().addTaskKey;
      return KeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: (event) {
          if (event is! KeyDownEvent) return;
          // 侧边栏打开或有 ModalRoute 覆盖时不触发
          if (_scaffoldKey.currentState?.isDrawerOpen == true) return;
          if (ModalRoute.of(this.context)?.isCurrent != true) return;
          final match = switch (addTaskKey) {
            'space' => event.logicalKey == LogicalKeyboardKey.space,
            'enter' => event.logicalKey == LogicalKeyboardKey.enter,
            _ => false,
          };
          if (match) showTodoEditSheet(this.context);
        },
        child: MouseRegion(
        onHover: (e) {
          final state = _scaffoldKey.currentState;
          if (state == null) return;
          if (!state.isDrawerOpen) {
            if (e.position.dx < 20) {
              _drawerAutoCloseTimer?.cancel();
              _drawerAutoCloseTimer = null;
              state.openDrawer();
            }
          } else {
            // 有 Dialog/DropdownMenu 覆盖在侧边栏上时，不触发自动关闭
            if (ModalRoute.of(this.context)?.isCurrent != true) {
              _drawerAutoCloseTimer?.cancel();
              _drawerAutoCloseTimer = null;
            } else if (e.position.dx <= 320) {
              _drawerAutoCloseTimer?.cancel();
              _drawerAutoCloseTimer = null;
            } else if (_drawerAutoCloseTimer == null) {
              _startDrawerAutoClose();
            }
          }
        },
        onExit: (_) {
          if (_scaffoldKey.currentState?.isDrawerOpen == true
              && _drawerAutoCloseTimer == null
              && ModalRoute.of(this.context)?.isCurrent == true) {
            _startDrawerAutoClose();
          }
        },
        child: scaffold,
      ),
    );
    });
  }
}
