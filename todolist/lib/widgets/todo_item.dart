import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/todo.dart';
import '../providers/todo_provider.dart';
import 'todo_edit_sheet.dart';

/// 全局通知：任何一项进入 armed 时广播自己的 id，其他项收到后重置
final armedNotifier = ValueNotifier<String?>(null);

/// 单个任务项，含完成动画和滑动删除（单层 GestureDetector 方案）
class TodoItem extends StatefulWidget {
  final Todo todo;

  const TodoItem({super.key, required this.todo});

  @override
  State<TodoItem> createState() => _TodoItemState();
}

class _TodoItemState extends State<TodoItem> with TickerProviderStateMixin {
  late final AnimationController _rippleController;
  late final AnimationController _fadeController;
  late final AnimationController _slideController;

  static const _armedOffset = -80.0;
  static const _armThreshold = -50.0;
  static const _deleteThreshold = -140.0;

  double _dragOffset = 0;
  bool _armed = false;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
      value: widget.todo.completed ? 1.0 : 0.0,
    );
    _slideController = AnimationController.unbounded(vsync: this, value: 0);
    armedNotifier.addListener(_onOtherArmed);
  }

  @override
  void didUpdateWidget(TodoItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.todo.completed != oldWidget.todo.completed) {
      if (widget.todo.completed) {
        _rippleController.forward(from: 0);
        _fadeController.forward();
      } else {
        _fadeController.reverse();
      }
    }
  }

  @override
  void dispose() {
    armedNotifier.removeListener(_onOtherArmed);
    _rippleController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  /// 其他项进入 armed 时，自己重置
  void _onOtherArmed() {
    if (_armed && armedNotifier.value != widget.todo.id) {
      setState(() => _armed = false);
      _animateTo(0);
    }
  }

  void _onToggle() {
    _resetArmed();
    context.read<TodoProvider>().toggleComplete(widget.todo.id);
  }

  void _onTap() {
    _resetArmed();
    showTodoEditSheet(context, todo: widget.todo);
  }

  void _resetArmed() {
    if (_armed) {
      setState(() => _armed = false);
      _animateTo(0);
    }
  }

  void _onDragStart(DragStartDetails d) {
    _dragging = true;
    _slideController.stop();
    _dragOffset = _slideController.value;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    _dragOffset += d.delta.dx;
    // 只允许左滑（负值），右滑最多回到 0
    _dragOffset = _dragOffset.clamp(-300.0, 0.0);
    _slideController.value = _dragOffset;
  }

  void _onDragEnd(DragEndDetails d) {
    _dragging = false;
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
        setState(() => _armed = false);
        _animateTo(0);
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
    context.read<TodoProvider>().deleteTodo(widget.todo.id);
  }

  void _deleteByTap() {
    _animateTo(-MediaQuery.of(context).size.width, onComplete: _delete);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final todo = widget.todo;
    // 计算删除区域的可见比例（用于动画效果）
    final revealRatio = (_slideController.value.abs() / 80).clamp(0.0, 1.0);

    return GestureDetector(
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: ClipRect(
        child: Stack(
          children: [
            // 底层：红色删除区域
            Positioned.fill(
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
                    GestureDetector(
                      onTap: _armed ? _deleteByTap : null,
                      child: Icon(Icons.delete_outline,
                        color: Color.lerp(
                          colorScheme.onErrorContainer.withValues(alpha: 0.5),
                          colorScheme.onError,
                          revealRatio,
                        ),
                        size: 24 + revealRatio * 4,
                      ),
                    ),
                    if (_armed)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('删除',
                          style: TextStyle(
                            color: colorScheme.onError,
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // 上层：内容，通过 AnimatedBuilder 控制偏移
            AnimatedBuilder(
              animation: _slideController,
              builder: (context, child) => Transform.translate(
                offset: Offset(_slideController.value, 0),
                child: child,
              ),
              child: _buildContent(context, colorScheme, todo),
            ),
          ],
        ),
      ),
    );
  }

  bool _isOverdue(Todo todo) =>
      todo.deadline != null &&
      !todo.completed &&
      todo.deadline!.isBefore(DateTime.now());

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
              value: todo.completed,
              onChanged: (_) => _onToggle(),
              shape: const CircleBorder(),
            ),
            title: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 300),
              style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                decoration: todo.completed ? TextDecoration.lineThrough : null,
                color: todo.completed
                    ? colorScheme.onSurface.withValues(alpha: 0.5)
                    : colorScheme.onSurface,
              ),
              child: Text(todo.title),
            ),
            subtitle: todo.deadline != null
                ? Text(
                    '${todo.deadline!.month}/${todo.deadline!.day} ${todo.deadline!.hour.toString().padLeft(2, '0')}:${todo.deadline!.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      color: todo.completed
                          ? colorScheme.onSurface.withValues(alpha: 0.3)
                          : _isOverdue(todo)
                              ? colorScheme.error
                              : colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  )
                : null,
            trailing: todo.remind
                ? Icon(Icons.notifications_active,
                    size: 16,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5))
                : null,
            onTap: _onTap,
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
