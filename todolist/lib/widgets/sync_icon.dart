import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/todo_provider.dart';

/// 同步状态图标
class SyncIcon extends StatefulWidget {
  const SyncIcon({super.key});

  @override
  State<SyncIcon> createState() => _SyncIconState();
}

class _SyncIconState extends State<SyncIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotationController;
  SyncStatus? _lastStatus;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = context.watch<TodoProvider>().syncStatus;
    final colorScheme = Theme.of(context).colorScheme;

    // 仅在状态变化时控制动画
    if (status != _lastStatus) {
      _lastStatus = status;
      if (status == SyncStatus.syncing) {
        _rotationController.repeat();
      } else if (_rotationController.isAnimating) {
        _rotationController.stop();
        _rotationController.reset();
      }
    }

    final Widget icon;
    final VoidCallback? onTap;

    switch (status) {
      case SyncStatus.idle:
        icon = Icon(Icons.sync, color: colorScheme.onSurfaceVariant);
        onTap = () => context.read<TodoProvider>().sync();
      case SyncStatus.syncing:
        icon = RotationTransition(
          turns: _rotationController,
          child: Icon(Icons.sync, color: colorScheme.primary),
        );
        onTap = null;
      case SyncStatus.success:
        icon = Icon(Icons.check_circle_outline, color: colorScheme.primary);
        onTap = null;
      case SyncStatus.error:
        icon = Icon(Icons.error_outline, color: colorScheme.error);
        onTap = () => context.read<TodoProvider>().sync();
    }

    return IconButton(onPressed: onTap, icon: icon);
  }
}
