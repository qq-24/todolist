import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/todo.dart';
import '../providers/todo_provider.dart';
import 'todo_edit_sheet.dart';

/// 全局通知：任何一项进入 armed 时广播自己的 id，其他项收到后重置
final armedNotifier = ValueNotifier<String?>(null);

/// 单个任务项，含完成动画和滑动删除（单层 GestureDetector 方案）
class TodoItem extends StatefulWidget {
  final Todo todo;
  final int? index; // 桌面端拖拽排序用

  const TodoItem({super.key, required this.todo, this.index});

  @override
  State<TodoItem> createState() => _TodoItemState();
}

class _TodoItemState extends State<TodoItem> with TickerProviderStateMixin {
  late final AnimationController _rippleController;
  late final AnimationController _fadeController;
  late final AnimationController _slideController;
  late final AnimationController _collapseController;

  static const _armedOffset = -80.0;
  static const _armThreshold = -50.0;
  static const _deleteThreshold = -140.0;

  double _dragOffset = 0;
  bool _armed = false;
  bool _pendingComplete = false;
  // 本地视觉状态：点击勾选后立即为 true，驱动 Checkbox 打勾和划线动画
  late bool _visualCompleted;

  @override
  void initState() {
    super.initState();
    _visualCompleted = widget.todo.completed;
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: widget.todo.completed ? 1.0 : 0.0,
    );
    _slideController = AnimationController.unbounded(vsync: this, value: 0);
    _collapseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1.0,
    );
    // 刚被 toggle 完成/取消完成的 item：从 0 展开入场
    final toggled = context.read<TodoProvider>().consumeLastToggledId();
    if (toggled == widget.todo.id) {
      _collapseController.value = 0.0;
      _collapseController.forward();
    }
    armedNotifier.addListener(_onOtherArmed);
  }

  @override
  void didUpdateWidget(TodoItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部数据变化（远端同步、取消完成等）时同步视觉状态
    if (widget.todo.completed != oldWidget.todo.completed) {
      if (_pendingComplete) {
        // 本地触发的完成，动画已在 _onToggle 中播放，只同步状态
        _visualCompleted = widget.todo.completed;
        _pendingComplete = false;
      } else {
        // 外部触发的变化（远端同步等）
        _visualCompleted = widget.todo.completed;
        if (widget.todo.completed) {
          _fadeController.forward();
        } else {
          _fadeController.reverse();
        }
      }
    }
  }

  @override
  void dispose() {
    armedNotifier.removeListener(_onOtherArmed);
    _rippleController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    _collapseController.dispose();
    super.dispose();
  }

  void _onOtherArmed() {
    if (_armed && armedNotifier.value != widget.todo.id) {
      _disarm();
    }
  }

  /// 统一的取消 armed 方法，同时重置 armedNotifier
  void _disarm() {
    if (!_armed) return;
    setState(() => _armed = false);
    // 如果当前 armedNotifier 指向自己，清空它以恢复 drawer
    if (armedNotifier.value == widget.todo.id) {
      armedNotifier.value = null;
    }
    _animateTo(0);
  }

  void _onToggle() {
    _disarm();
    final todo = widget.todo;
    if (!todo.completed) {
      if (_pendingComplete) return; // 防止快速双击
      _pendingComplete = true;

      // 立即更新视觉状态：Checkbox 打勾 + 划线
      setState(() => _visualCompleted = true);
      _rippleController.forward(from: 0);
      _fadeController.forward();

      if (todo.repeatMode != TodoRepeatMode.none && todo.deadline != null) {
        // 重复任务：涟漪后推截止时间，恢复视觉状态
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted) {
            context.read<TodoProvider>().toggleComplete(todo.id);
            // 重复任务完成后不标记 completed，恢复视觉
            setState(() => _visualCompleted = false);
            _fadeController.reverse();
          }
          _pendingComplete = false;
        });
      } else {
        // 普通任务：勾选+划线动画后挤扁，再 toggleComplete，条目跳到已完成区
        Future.delayed(const Duration(milliseconds: 400), () {
          if (!mounted) return;
          _collapseController.reverse().then((_) {
            if (!mounted) return;
            context.read<TodoProvider>().toggleComplete(todo.id);
            _collapseController.value = 1.0;
          });
        });
      }
    } else {
      // 取消完成：挤扁后移回未完成区
      setState(() => _visualCompleted = false);
      _fadeController.reverse();
      _collapseController.reverse().then((_) {
        if (!mounted) return;
        context.read<TodoProvider>().toggleComplete(todo.id);
        _collapseController.value = 1.0;
      });
    }
  }

  void _onTap() {
    _disarm();
    showTodoEditSheet(context, todo: widget.todo);
  }

  void _onDragStart(DragStartDetails d) {
    _slideController.stop();
    _dragOffset = _slideController.value;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    _dragOffset += d.delta.dx;
    _dragOffset = _dragOffset.clamp(-300.0, 0.0);
    _slideController.value = _dragOffset;
  }

  void _onDragEnd(DragEndDetails d) {
    if (!_armed) {
      if (_dragOffset < _armThreshold) {
        setState(() => _armed = true);
        armedNotifier.value = widget.todo.id;
        _animateTo(_armedOffset);
      } else {
        _animateTo(0);
      }
    } else {
      if (_dragOffset < _deleteThreshold) {
        _animateTo(-MediaQuery.of(context).size.width, onComplete: _delete);
      } else if (_dragOffset > _armThreshold / 2) {
        _disarm();
      } else {
        _animateTo(_armedOffset);
      }
    }
  }

  void _animateTo(double target, {VoidCallback? onComplete}) {
    _slideController
        .animateTo(target,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic)
        .then((_) {
      if (!mounted) return;
      _dragOffset = target;
      onComplete?.call();
    });
  }

  void _delete() {
    if (_isDesktop) {
      // 桌面端：确认对话框
      final provider = context.read<TodoProvider>();
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('确认删除'),
          content: Text('确定要删除"${widget.todo.title}"吗？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
          ],
        ),
      ).then((confirmed) {
        if (confirmed == true) {
          provider.deleteTodo(widget.todo.id);
        }
      });
    } else {
      // 移动端：挤扁动画后删除，SnackBar 带撤销
      _collapseAndDelete();
    }
  }

  static final bool _isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  void _deleteByTap() {
    _animateTo(-MediaQuery.of(context).size.width, onComplete: _collapseAndDelete);
  }

  void _collapseAndDelete() {
    final provider = context.read<TodoProvider>();
    final todo = widget.todo;
    _collapseController.reverse().then((_) {
      if (!mounted) return;
      provider.deleteTodo(todo.id);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('已删除"${todo.title}"'),
        action: SnackBarAction(label: '撤销', onPressed: () => provider.addTodo(todo)),
        duration: const Duration(seconds: 4),
      ));
    });
  }

  void _showMobileLongPressSheet(BuildContext context) {
    final isWish = widget.todo.kind == TodoKind.wish;
    final provider = context.read<TodoProvider>();
    showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.edit), title: const Text('编辑'), onTap: () => Navigator.pop(ctx, 'edit')),
            ListTile(
              leading: Icon(isWish ? Icons.checklist : Icons.auto_awesome),
              title: Text(isWish ? '升级成任务' : '放回想做的'),
              onTap: () => Navigator.pop(ctx, isWish ? 'promote' : 'demote'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('删除', style: TextStyle(color: Colors.red)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    ).then((v) {
      if (!mounted || v == null) return;
      switch (v) {
        case 'edit': _onTap();
        case 'promote': provider.promoteToTask(widget.todo.id);
        case 'demote': provider.demoteToWish(widget.todo.id);
        case 'delete': _delete();
      }
    });
  }

  void _showContextMenu(TapDownDetails details) {
    final pos = details.globalPosition;
    final isWish = widget.todo.kind == TodoKind.wish;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit), title: Text('编辑'), dense: true)),
        const PopupMenuItem(value: 'toggle', child: ListTile(leading: Icon(Icons.check), title: Text('切换完成'), dense: true)),
        PopupMenuItem(
          value: isWish ? 'promote' : 'demote',
          child: ListTile(
            leading: Icon(isWish ? Icons.checklist : Icons.auto_awesome),
            title: Text(isWish ? '升级成任务' : '放回想做的'),
            dense: true,
          ),
        ),
        const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline, color: Colors.red), title: Text('删除', style: TextStyle(color: Colors.red)), dense: true)),
      ],
    ).then((v) {
      if (!mounted || v == null) return;
      switch (v) {
        case 'edit': _onTap();
        case 'toggle': _onToggle();
        case 'promote': context.read<TodoProvider>().promoteToTask(widget.todo.id);
        case 'demote': context.read<TodoProvider>().demoteToWish(widget.todo.id);
        case 'delete': _delete();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final todo = widget.todo;
    final content = _buildContent(context, colorScheme, todo);

    // 桌面端：右键菜单，无滑动删除
    if (_isDesktop) {
      return SizeTransition(
        sizeFactor: _collapseController,
        child: GestureDetector(
          onSecondaryTapDown: _showContextMenu,
          child: content,
        ),
      );
    }

    // 移动端：滑动删除 + 挤扁动画
    return SizeTransition(
      sizeFactor: _collapseController,
      child: GestureDetector(
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: AnimatedBuilder(
        animation: _slideController,
        builder: (context, child) {
          final offset = _slideController.value;
          final revealRatio = (offset.abs() / 80).clamp(0.0, 1.0);
          final showDelete = offset < -1; // 只在有偏移时显示红色底层

          return ClipRect(
            child: Stack(
              children: [
                // 底层：红色删除区域（只在滑动时显示）
                if (showDelete)
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: _armed ? _deleteByTap : null,
                      child: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        color: Color.lerp(
                          colorScheme.errorContainer.withValues(alpha: 0.3),
                          colorScheme.error,
                          revealRatio,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.delete_outline,
                              color: Color.lerp(
                                colorScheme.onErrorContainer.withValues(alpha: 0.5),
                                colorScheme.onError,
                                revealRatio,
                              ),
                              size: 24 + revealRatio * 4,
                            ),
                            if (_armed)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text('删除',
                                  style: TextStyle(color: colorScheme.onError, fontSize: 11),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                // 上层：内容
                Transform.translate(
                  offset: Offset(offset, 0),
                  child: child,
                ),
              ],
            ),
          );
        },
        child: _buildContent(context, colorScheme, todo),
      ),
    ),
    );
  }

  bool _isOverdue(Todo todo) =>
      todo.kind != TodoKind.wish &&
      todo.deadline != null &&
      !todo.completed &&
      todo.deadline!.isBefore(DateTime.now());

  Widget _buildDesktopTrailing(BuildContext context, ColorScheme colorScheme, Todo todo) {
    final children = <Widget>[];
    if (widget.index != null) {
      children.add(ReorderableDragStartListener(
        index: widget.index!,
        child: Icon(Icons.drag_handle, size: 20,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
      ));
    }
    if (todo.remind && todo.kind != TodoKind.wish) {
      children.add(Padding(
        padding: EdgeInsets.only(top: widget.index != null ? 4 : 0),
        child: Icon(Icons.notifications_active, size: 14,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
      ));
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(mainAxisSize: MainAxisSize.min, children: children);
  }

  Widget _buildContent(BuildContext context, ColorScheme colorScheme, Todo todo) {
    return AnimatedBuilder(
      animation: _fadeController,
      builder: (context, child) {
        final bgColor = ColorTween(
          begin: Theme.of(context).scaffoldBackgroundColor,
          end: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        ).evaluate(_fadeController);
        return Container(color: bgColor, child: child);
      },
      child: Stack(
        children: [
          if (_rippleController.isAnimating || _rippleController.value > 0)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _rippleController,
                builder: (context, _) => CustomPaint(
                  painter: _RipplePainter(
                    progress: _rippleController.value,
                    color: colorScheme.primary.withValues(alpha: 0.15),
                  ),
                ),
              ),
            ),
          ListTile(
            leading: Checkbox(
              value: _visualCompleted,
              onChanged: (_) => _onToggle(),
              shape: const CircleBorder(),
            ),
            title: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 300),
              style: todo.kind == TodoKind.wish
                  ? GoogleFonts.notoSerifSc(
                      decoration: _visualCompleted ? TextDecoration.lineThrough : null,
                      color: _visualCompleted
                          ? colorScheme.onSurface.withValues(alpha: 0.5)
                          : colorScheme.onSurface,
                      fontSize: 16,
                      height: 1.5,
                    )
                  : Theme.of(context).textTheme.bodyLarge!.copyWith(
                      decoration: _visualCompleted ? TextDecoration.lineThrough : null,
                      color: _visualCompleted
                          ? colorScheme.onSurface.withValues(alpha: 0.5)
                          : colorScheme.onSurface,
                    ),
              child: Text(todo.title),
            ),
            subtitle: todo.kind != TodoKind.wish && todo.deadline != null
                ? Text(
                    '${todo.deadline!.month}/${todo.deadline!.day} ${todo.deadline!.hour.toString().padLeft(2, '0')}:${todo.deadline!.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      color: _visualCompleted
                          ? colorScheme.onSurface.withValues(alpha: 0.3)
                          : _isOverdue(todo)
                              ? colorScheme.error
                              : colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  )
                : null,
            trailing: _isDesktop
                ? _buildDesktopTrailing(context, colorScheme, todo)
                : (todo.remind && todo.kind != TodoKind.wish)
                    ? Icon(Icons.notifications_active,
                        size: 16,
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5))
                    : null,
            onTap: _onTap,
            onLongPress: !_isDesktop ? () => _showMobileLongPressSheet(context) : null,
          ),
        ],
      ),
    );
  }
}

/// 涟漪扩散画笔
class _RipplePainter extends CustomPainter {
  final double progress;
  final Color color;

  _RipplePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final center = Offset(40, size.height / 2);
    final maxRadius = sqrt(size.width * size.width + size.height * size.height);
    final paint = Paint()
      ..color = color.withValues(alpha: color.a * (1 - progress))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, maxRadius * progress, paint);
  }

  @override
  bool shouldRepaint(_RipplePainter old) =>
      old.progress != progress || old.color != color;
}
