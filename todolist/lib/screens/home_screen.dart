import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/todo_provider.dart';
import '../widgets/app_drawer.dart';
import '../widgets/sync_icon.dart';
import '../widgets/todo_edit_sheet.dart';
import '../widgets/todo_item.dart';

/// 主界面
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final TodoProvider _provider;
  bool _isConflictDialogShowing = false;

  @override
  void initState() {
    super.initState();
    _provider = context.read<TodoProvider>();
    _provider.addListener(_onProviderChanged);
  }

  @override
  void dispose() {
    _provider.removeListener(_onProviderChanged);
    super.dispose();
  }

  void _onProviderChanged() {
    if (!mounted) return;
    if (_provider.hasConflict && !_isConflictDialogShowing) {
      _showConflictDialog();
    }
  }

  void _showConflictDialog() {
    _isConflictDialogShowing = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('同步冲突'),
        content: const Text('本地和远端数据都有修改，请选择保留哪个版本。'),
        actions: [
          TextButton(
            onPressed: () {
              _provider.resolveConflict(false);
              Navigator.of(ctx).pop();
            },
            child: const Text('保留远端'),
          ),
          FilledButton(
            onPressed: () {
              _provider.resolveConflict(true);
              Navigator.of(ctx).pop();
            },
            child: const Text('保留本地'),
          ),
        ],
      ),
    ).then((_) => _isConflictDialogShowing = false);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TodoProvider>();
    final todos = provider.sortedTodos;

    return ValueListenableBuilder<String?>(
      valueListenable: armedNotifier,
      builder: (context, armedId, _) => Scaffold(
      appBar: AppBar(
        title: const Text('Todo'),
        actions: const [SyncIcon()],
      ),
      drawer: const AppDrawer(),
      drawerEdgeDragWidth: armedId != null ? 0 : MediaQuery.of(context).size.width * 0.5,
      body: todos.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 64,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.2)),
                  const SizedBox(height: 16),
                  Text(
                    '点击 + 添加第一个任务',
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
          : ReorderableListView.builder(
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
                return TodoItem(key: ValueKey(todo.id), todo: todo);
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showTodoEditSheet(context),
        child: const Icon(Icons.add),
      ),
    ));
  }
}
