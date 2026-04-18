# 重复提醒功能

## Requirements

### R1: 重复提醒
- 描述：任务支持按周期重复，完成后自动推截止时间到下一周期并重置为未完成
- 验收标准：
  - [ ] Todo 模型新增 repeatMode 字段（none/daily/weekly/monthly/yearly）
  - [ ] 编辑面板提醒区域新增重复周期选择
  - [ ] 完成重复任务后截止时间自动推到下一周期
  - [ ] 完成重复任务后任务恢复未完成状态
  - [ ] 重复任务完成后提醒自动重新调度
  - [ ] 旧数据兼容（无 repeatMode 字段默认 none）

## Technical Design

### 详细设计

#### 文件：lib/models/todo.dart（修改）

新增 RepeatMode 枚举：
```dart
enum RepeatMode {
  none,    // 不重复
  daily,   // 每天
  weekly,  // 每周
  monthly, // 每月
  yearly;  // 每年

  String get label => switch (this) {
    none => '不重复',
    daily => '每天',
    weekly => '每周',
    monthly => '每月',
    yearly => '每年',
  };
}
```

Todo 类新增字段：
- `RepeatMode repeatMode`，默认 `RepeatMode.none`
- toJson 中序列化：`'repeatMode': repeatMode.name`
- fromJson 中反序列化：安全解析，默认 none
- copyWith 中支持

新增静态方法计算下一个周期：
```dart
static DateTime nextOccurrence(DateTime current, RepeatMode mode) {
  return switch (mode) {
    RepeatMode.none => current,
    RepeatMode.daily => current.add(Duration(days: 1)),
    RepeatMode.weekly => current.add(Duration(days: 7)),
    RepeatMode.monthly => DateTime(current.year, current.month + 1, current.day, current.hour, current.minute),
    RepeatMode.yearly => DateTime(current.year + 1, current.month, current.day, current.hour, current.minute),
  };
}
```

#### 文件：lib/providers/todo_provider.dart（修改）

修改 `toggleComplete` 方法：
- 当任务被标记完成且 `repeatMode != none` 且有 deadline 时：
  - 不标记 completed = true
  - 而是把 deadline 推到下一个周期（调用 nextOccurrence）
  - 更新 updatedAt
  - 重新调度提醒
- 当任务被标记完成且 `repeatMode == none` 时：保持现有逻辑

#### 文件：lib/widgets/todo_edit_sheet.dart（修改）

在提醒开关打开后、震动模式选择条之前，新增重复周期选择：
- 用 FittedBox 包裹 SegmentedButton<RepeatMode>
- 5 个选项：不重复/每天/每周/每月/每年
- 默认值：RepeatMode.none
- 编辑模式下从 todo.repeatMode 读取

#### 文件：lib/widgets/todo_item.dart（修改）

在 `_onToggle` 中，如果是重复任务，不走淡出沉底动画，而是播放一个"刷新"效果（涟漪动画后恢复原样，因为任务不会沉底）。

## Tasks

### Task 1: Todo 模型新增 RepeatMode
- 涉及文件：lib/models/todo.dart
- 修改说明：新增 RepeatMode 枚举 + Todo 字段 + 序列化 + nextOccurrence 方法
- 验证方式：编译通过，旧 JSON 数据能正常解析

### Task 2: toggleComplete 支持重复任务
- 涉及文件：lib/providers/todo_provider.dart
- 前置依赖：Task 1
- 修改说明：toggleComplete 中检测 repeatMode，重复任务推截止时间而非标记完成
- 验证方式：完成重复任务后截止时间变为下一周期，任务保持未完成

### Task 3: 编辑面板新增重复选择
- 涉及文件：lib/widgets/todo_edit_sheet.dart
- 前置依赖：Task 1
- 修改说明：提醒区域新增 FittedBox + SegmentedButton<RepeatMode>
- 验证方式：UI 显示正确，选择后保存到 todo

### Task 4: todo_item 重复任务完成动画调整
- 涉及文件：lib/widgets/todo_item.dart
- 前置依赖：Task 2
- 修改说明：重复任务完成时只播涟漪不沉底
- 验证方式：重复任务勾选后播放涟漪动画，任务留在原位
