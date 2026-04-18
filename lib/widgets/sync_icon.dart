import 'dart:io';

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
  bool _isDialogShowing = false;

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
    final provider = context.watch<TodoProvider>();
    final status = provider.syncStatus;
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

      // 手机端同步错误弹窗
      if (status == SyncStatus.error && Platform.isAndroid && !_isDialogShowing) {
        _isDialogShowing = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) { _isDialogShowing = false; return; }
          final reason = provider.lastError ?? '同步失败';
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('同步失败'),
              content: Text(reason),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('知道了'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    provider.sync();
                  },
                  child: const Text('重试'),
                ),
              ],
            ),
          ).then((_) => _isDialogShowing = false);
        });
      }
    }

    final Widget icon;
    final VoidCallback? onTap;
    final String tooltip;

    switch (status) {
      case SyncStatus.idle:
        icon = Icon(Icons.sync, color: colorScheme.onSurfaceVariant);
        onTap = () => provider.sync();
        tooltip = '点击同步';
      case SyncStatus.syncing:
        icon = RotationTransition(
          turns: _rotationController,
          child: Icon(Icons.sync, color: colorScheme.primary),
        );
        onTap = null;
        tooltip = '同步中...';
      case SyncStatus.success:
        icon = Icon(Icons.check_circle_outline, color: colorScheme.primary);
        onTap = null;
        tooltip = '同步成功';
      case SyncStatus.error:
        // 由下方 if 分支单独处理，这里只是占位
        icon = const SizedBox.shrink();
        onTap = null;
        tooltip = '';
    }

    // error 状态用自定义布局显示错误原因文字
    if (status == SyncStatus.error) {
      final reason = provider.lastError ?? '同步失败';
      return InkWell(
        onTap: () => provider.sync(),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(reason, style: TextStyle(color: colorScheme.error, fontSize: 12),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 4),
              Icon(Icons.error_outline, color: colorScheme.error, size: 20),
            ],
          ),
        ),
      );
    }

    return IconButton(onPressed: onTap, icon: icon, tooltip: tooltip);
  }
}
