import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  TodoRepeatMode _repeatMode = TodoRepeatMode.none;
  bool _saving = false;
  bool _saved = false;
  late TodoKind _kind;

  bool get _isEdit => widget.todo != null;

  @override
  void initState() {
    super.initState();
    _kind = widget.todo?.kind ?? TodoKind.task;
    _titleController = TextEditingController(text: widget.todo?.title ?? '');
    _descController =
        TextEditingController(text: widget.todo?.description ?? '');
    _deadline = widget.todo?.deadline;
    _remind = widget.todo?.remind ?? false;
    _reminderAdvances =
        widget.todo?.reminderAdvances ?? {ReminderAdvance.atTime};
    _vibrationMode = widget.todo?.vibrationMode ?? VibrationMode.continuous;
    _repeatMode = widget.todo?.repeatMode ?? TodoRepeatMode.none;
    _titleController.addListener(_onChanged);
    _descController.addListener(_onChanged);
    if (!_isEdit) _loadDraft();
  }

  @override
  void dispose() {
    if (!_isEdit && !_saved) {
      // 同步缓存 controller 值，避免 async _saveDraft 访问已销毁的 controller
      final cachedTitle = _titleController.text;
      final cachedDesc = _descController.text;
      _saveDraftWithValues(cachedTitle, cachedDesc);
    }
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  Future<void> _loadDraft() async {
    final p = await SharedPreferences.getInstance();
    // 如果用户已开始输入，不覆盖
    if (_titleController.text.isNotEmpty || _descController.text.isNotEmpty) return;
    final t = p.getString('draft_title');
    final d = p.getString('draft_desc');
    final dl = p.getString('draft_deadline');
    if (t != null && t.isNotEmpty) _titleController.text = t;
    if (d != null && d.isNotEmpty) _descController.text = d;
    setState(() {
      if (dl != null) {
        final parsed = DateTime.tryParse(dl);
        if (parsed != null) _deadline = parsed;
      }
      _remind = p.getBool('draft_remind') ?? false;
      final advStr = p.getString('draft_reminderAdvances');
      if (advStr != null && advStr.isNotEmpty) {
        _reminderAdvances = advStr.split(',').map((n) =>
          ReminderAdvance.values.firstWhere((v) => v.name == n, orElse: () => ReminderAdvance.atTime)
        ).toSet();
      }
      final vmStr = p.getString('draft_vibrationMode');
      if (vmStr != null) {
        _vibrationMode = VibrationMode.values.firstWhere((v) => v.name == vmStr, orElse: () => VibrationMode.continuous);
      }
      final rmStr = p.getString('draft_repeatMode');
      if (rmStr != null) {
        _repeatMode = TodoRepeatMode.values.firstWhere((v) => v.name == rmStr, orElse: () => TodoRepeatMode.none);
      }
    });
  }

  Future<void> _saveDraftWithValues(String title, String desc) async {
    final p = await SharedPreferences.getInstance();
    final t = title.trim();
    if (t.isEmpty && desc.trim().isEmpty && _deadline == null) {
      await _clearDraft();
    } else {
      await p.setString('draft_title', title);
      await p.setString('draft_desc', desc);
      if (_deadline != null) {
        await p.setString('draft_deadline', _deadline!.toIso8601String());
      } else {
        await p.remove('draft_deadline');
      }
      await p.setBool('draft_remind', _remind);
      await p.setString('draft_reminderAdvances', _reminderAdvances.map((e) => e.name).join(','));
      await p.setString('draft_vibrationMode', _vibrationMode.name);
      await p.setString('draft_repeatMode', _repeatMode.name);
    }
  }

  Future<void> _clearDraft() async {
    final p = await SharedPreferences.getInstance();
    await p.remove('draft_title');
    await p.remove('draft_desc');
    await p.remove('draft_deadline');
    await p.remove('draft_remind');
    await p.remove('draft_reminderAdvances');
    await p.remove('draft_vibrationMode');
    await p.remove('draft_repeatMode');
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final init = _deadline ?? now;
    final result = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _DateTimePicker(initial: init, firstDate: now.subtract(const Duration(days: 1))),
    );
    if (result != null && mounted) {
      setState(() => _deadline = result);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    setState(() => _saving = true);

    // 过期截止时间警告
    if (_deadline != null && _deadline!.isBefore(DateTime.now())) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('截止时间已过，提醒将不会触发')),
        );
      }
    }

    final provider = context.read<TodoProvider>();

    try {
      if (_isEdit) {
        final updated = widget.todo!.copyWith(
          title: title,
          description: _descController.text.trim(),
          kind: _kind,
          deadline: _kind == TodoKind.wish ? null : _deadline,
          remind: _kind == TodoKind.wish ? false : _remind,
          reminderAdvances: _kind == TodoKind.wish ? {ReminderAdvance.atTime} : _reminderAdvances,
          vibrationMode: _kind == TodoKind.wish ? VibrationMode.continuous : _vibrationMode,
          repeatMode: _kind == TodoKind.wish ? TodoRepeatMode.none : _repeatMode,
          updatedAt: DateTime.now(),
        );
        await provider.updateTodo(updated);
      } else {
        final todo = Todo(
          title: title,
          description: _descController.text.trim(),
          kind: _kind,
          deadline: _deadline,
          remind: _remind,
          reminderAdvances: _reminderAdvances,
          vibrationMode: _vibrationMode,
          repeatMode: _repeatMode,
        );
        await provider.addTodo(todo);
        _saved = true;
        await _clearDraft();
      }

      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 100),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom + 24,
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

          // 类型选择
          SegmentedButton<TodoKind>(
            segments: const [
              ButtonSegment(value: TodoKind.task, icon: Icon(Icons.checklist), label: Text('要做的')),
              ButtonSegment(value: TodoKind.wish, icon: Icon(Icons.auto_awesome), label: Text('想做的')),
            ],
            selected: {_kind},
            onSelectionChanged: (v) => setState(() {
              _kind = v.first;
              if (_kind == TodoKind.wish) {
                _deadline = null;
                _remind = false;
                _repeatMode = TodoRepeatMode.none;
                _reminderAdvances = {ReminderAdvance.atTime};
                _vibrationMode = VibrationMode.continuous;
              }
            }),
          ),
          const SizedBox(height: 12),

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
          if (_kind != TodoKind.wish) ...[
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
                      _repeatMode = TodoRepeatMode.none;
                      _reminderAdvances = {ReminderAdvance.atTime};
                      _vibrationMode = VibrationMode.continuous;
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
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SegmentedButton<ReminderAdvance>(
                    multiSelectionEnabled: true,
                    emptySelectionAllowed: false,
                    segments: ReminderAdvance.values
                        .map((e) => ButtonSegment(
                              value: e,
                              label: Text(e.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    selected: _reminderAdvances,
                    onSelectionChanged: (v) =>
                        setState(() => _reminderAdvances = v),
                  ),
                ),
              ),
            if (_remind)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SegmentedButton<TodoRepeatMode>(
                    segments: TodoRepeatMode.values
                        .map((e) => ButtonSegment(
                              value: e,
                              label: Text(e.label, maxLines: 1),
                            ))
                        .toList(),
                    selected: {_repeatMode},
                    onSelectionChanged: (v) =>
                        setState(() => _repeatMode = v.first),
                  ),
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

          ], // _kind != TodoKind.wish

          const SizedBox(height: 8),

          // 保存按钮
          FilledButton(
            onPressed: (_saving || _titleController.text.trim().isEmpty) ? null : _save,
            child: Text(_isEdit ? '保存' : (_kind == TodoKind.wish ? '收进来' : '添加')),
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

/// 日期+时间合并选择器（底部弹出）
class _DateTimePicker extends StatefulWidget {
  final DateTime initial;
  final DateTime firstDate;
  const _DateTimePicker({required this.initial, required this.firstDate});

  @override
  State<_DateTimePicker> createState() => _DateTimePickerState();
}

class _DateTimePickerState extends State<_DateTimePicker> {
  late DateTime _selectedDate;
  late int _hour;
  late int _minute;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime(widget.initial.year, widget.initial.month, widget.initial.day);
    _hour = widget.initial.hour;
    _minute = widget.initial.minute;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 顶部栏
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
                const Spacer(),
                Text('选择日期和时间', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context, DateTime(
                    _selectedDate.year, _selectedDate.month, _selectedDate.day,
                    _hour, _minute,
                  )),
                  child: const Text('确定'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 日期选择（CalendarDatePicker 内嵌）
          SizedBox(
            height: 360,
            child: Theme(
              data: Theme.of(context).copyWith(
                datePickerTheme: DatePickerThemeData(
                  dayStyle: const TextStyle(fontSize: 16),
                  todayForegroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return Theme.of(context).colorScheme.onPrimary;
                    }
                    return Theme.of(context).colorScheme.primary;
                  }),
                  dayOverlayColor: const WidgetStatePropertyAll(Colors.transparent),
                  dayForegroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return Theme.of(context).colorScheme.onPrimary;
                    }
                    return null;
                  }),
                  dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return Theme.of(context).colorScheme.primary;
                    }
                    return null;
                  }),
                ),
              ),
              child: CalendarDatePicker(
                initialDate: _selectedDate,
                firstDate: widget.firstDate,
                lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                onDateChanged: (d) => _selectedDate = d,
              ),
            ),
          ),
          const Divider(height: 1),
          // 时间滚轮（拦截鼠标滚轮事件防止冒泡到 BottomSheet）
          Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                GestureBinding.instance.pointerSignalResolver.register(event, (event) {});
              }
            },
            child: SizedBox(
            height: 180,
            child: Row(
              children: [
                Expanded(
                  child: ListWheelScrollView.useDelegate(
                    itemExtent: 48,
                    diameterRatio: 1.5,
                    physics: const FixedExtentScrollPhysics(),
                    controller: FixedExtentScrollController(initialItem: _hour),
                    onSelectedItemChanged: (i) => _hour = i,
                    childDelegate: ListWheelChildBuilderDelegate(
                      childCount: 24,
                      builder: (ctx, i) => Center(
                        child: Text('$i 时', style: TextStyle(fontSize: 18, color: colorScheme.onSurface)),
                      ),
                    ),
                  ),
                ),
                Text(':', style: TextStyle(fontSize: 24, color: colorScheme.onSurface)),
                Expanded(
                  child: ListWheelScrollView.useDelegate(
                    itemExtent: 48,
                    diameterRatio: 1.5,
                    physics: const FixedExtentScrollPhysics(),
                    controller: FixedExtentScrollController(initialItem: _minute),
                    onSelectedItemChanged: (i) => _minute = i,
                    childDelegate: ListWheelChildBuilderDelegate(
                      childCount: 60,
                      builder: (ctx, i) => Center(
                        child: Text('${i.toString().padLeft(2, '0')} 分', style: TextStyle(fontSize: 18, color: colorScheme.onSurface)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }
}
