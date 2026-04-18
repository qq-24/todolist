import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/todo.dart';
import '../providers/todo_provider.dart';

/// 底部半屏编辑面板
class TodoEditSheet extends StatefulWidget {
  final Todo? todo; // null 表示新建模式

  const TodoEditSheet({super.key, this.todo});

  @override
  State<TodoEditSheet> createState() => _TodoEditSheetState();
}

class _TodoEditSheetState extends State<TodoEditSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _descController;
  DateTime? _deadline;
  bool _remind = false;
  Set<ReminderAdvance> _reminderAdvances = {ReminderAdvance.atTime};
  VibrationMode _vibrationMode = VibrationMode.continuous;

  bool get _isEdit => widget.todo != null;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.todo?.title ?? '');
    _descController =
        TextEditingController(text: widget.todo?.description ?? '');
    _deadline = widget.todo?.deadline;
    _remind = widget.todo?.remind ?? false;
    _reminderAdvances =
        widget.todo?.reminderAdvances ?? {ReminderAdvance.atTime};
    _vibrationMode = widget.todo?.vibrationMode ?? VibrationMode.continuous;
    _titleController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _deadline ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime:
          _deadline != null ? TimeOfDay.fromDateTime(_deadline!) : TimeOfDay.now(),
    );
    if (time == null || !mounted) return;

    setState(() {
      _deadline = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    // 过期截止时间警告
    if (_deadline != null && _deadline!.isBefore(DateTime.now())) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('截止时间已过，提醒将不会触发')),
        );
      }
    }

    final provider = context.read<TodoProvider>();

    if (_isEdit) {
      final updated = widget.todo!.copyWith(
        title: title,
        description: _descController.text.trim(),
        deadline: _deadline,
        remind: _remind,
        reminderAdvances: _reminderAdvances,
        vibrationMode: _vibrationMode,
        updatedAt: DateTime.now(),
      );
      await provider.updateTodo(updated);
    } else {
      final todo = Todo(
        title: title,
        description: _descController.text.trim(),
        deadline: _deadline,
        remind: _remind,
        reminderAdvances: _reminderAdvances,
        vibrationMode: _vibrationMode,
      );
      await provider.addTodo(todo);
    }

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom +
            24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 拖拽指示条
          Center(
            child: Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 标题
          TextField(
            controller: _titleController,
            autofocus: !_isEdit,
            decoration: const InputDecoration(
              labelText: '标题',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),

          // 描述
          TextField(
            controller: _descController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '描述',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),

          // 截止时间
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: Text(
              _deadline != null
                  ? '${_deadline!.month}/${_deadline!.day} ${_deadline!.hour.toString().padLeft(2, '0')}:${_deadline!.minute.toString().padLeft(2, '0')}'
                  : '设置截止时间',
            ),
            trailing: _deadline != null
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() {
                      _deadline = null;
                      _remind = false;
                    }),
                  )
                : null,
            onTap: _pickDateTime,
          ),

          // 提醒开关
          if (_deadline != null) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('提醒'),
              secondary: const Icon(Icons.notifications_outlined),
              value: _remind,
              onChanged: (v) => setState(() => _remind = v),
            ),
            // 提前量选择
            if (_remind)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SegmentedButton<ReminderAdvance>(
                  multiSelectionEnabled: true,
                  emptySelectionAllowed: false,
                  segments: ReminderAdvance.values
                      .map((e) => ButtonSegment(
                            value: e,
                            label: Text(e.label, style: const TextStyle(fontSize: 12)),
                          ))
                      .toList(),
                  selected: _reminderAdvances,
                  onSelectionChanged: (v) =>
                      setState(() => _reminderAdvances = v),
                ),
              ),
            if (_remind)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SegmentedButton<VibrationMode>(
                  segments: VibrationMode.values
                      .map((e) => ButtonSegment(
                            value: e,
                            label: Text(e.label, style: const TextStyle(fontSize: 12)),
                          ))
                      .toList(),
                  selected: {_vibrationMode},
                  onSelectionChanged: (v) =>
                      setState(() => _vibrationMode = v.first),
                ),
              ),
          ],

          const SizedBox(height: 8),

          // 保存按钮
          FilledButton(
            onPressed: _titleController.text.trim().isEmpty ? null : _save,
            child: Text(_isEdit ? '保存' : '添加'),
          ),
        ],
      ),
    );
  }
}

/// 显示编辑面板的便捷方法
void showTodoEditSheet(BuildContext context, {Todo? todo}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    builder: (_) => TodoEditSheet(todo: todo),
  );
}
