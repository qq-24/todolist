import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

/// 用于 copyWith 中区分"未传参"和"显式传 null"的哨兵值
const Object _sentinel = Object();

/// 类型：要做的任务 / 想做的心愿
enum TodoKind {
  task,
  wish;

  String get label => switch (this) {
        task => '要做的',
        wish => '想做的',
      };
}

/// 震动模式
enum VibrationMode {
  continuous, // 持续震动（每 5.5 秒重复，60 秒后停止）
  once;       // 仅震动一轮

  String get label => switch (this) {
    continuous => '持续震动',
    once => '震动一次',
  };
}

/// 重复模式
enum TodoRepeatMode {
  none,
  daily,
  weekly,
  monthly,
  yearly;

  String get label => switch (this) {
    none => '不重复',
    daily => '每天',
    weekly => '每周',
    monthly => '每月',
    yearly => '每年',
  };

  /// 计算下一个周期的时间（originalDay 用于月/年重复保留原始日期）
  DateTime nextOccurrence(DateTime current, {int? originalDay}) => switch (this) {
    none => current,
    daily => current.add(const Duration(days: 1)),
    weekly => current.add(const Duration(days: 7)),
    monthly => _clampedDate(current.year, current.month + 1, originalDay ?? current.day, current.hour, current.minute),
    yearly => _clampedDate(current.year + 1, current.month, originalDay ?? current.day, current.hour, current.minute),
  };

  static DateTime _clampedDate(int year, int month, int day, int hour, int minute) {
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, day > lastDay ? lastDay : day, hour, minute);
  }
}

/// 提醒提前量
enum ReminderAdvance {
  atTime, // 到期时
  min15, // 提前15分钟
  hour1, // 提前1小时
  day1, // 提前1天
  morning7; // 当天早上7点

  /// 转换为 Duration 偏移量（morning7 返回 Duration.zero，需特殊处理）
  Duration get offset => switch (this) {
    atTime => Duration.zero,
    min15 => const Duration(minutes: 15),
    hour1 => const Duration(hours: 1),
    day1 => const Duration(days: 1),
    morning7 => Duration.zero,
  };

  String get label => switch (this) {
    atTime => '到期时',
    min15 => '15分钟前',
    hour1 => '1小时前',
    day1 => '1天前',
    morning7 => '当天7点',
  };
}

class Todo {
  final String id;
  String title;
  String description;
  TodoKind kind;
  DateTime? deadline;
  int? originalDeadlineDay; // 用户设置 deadline 时的原始日期（day of month），防止月末塌陷
  bool remind;
  Set<ReminderAdvance> reminderAdvances; // 多选提前量
  VibrationMode vibrationMode;
  TodoRepeatMode repeatMode;
  bool completed;
  int sortIndex;
  final DateTime createdAt;
  DateTime updatedAt;

  Todo({
    String? id,
    required this.title,
    this.description = '',
    this.kind = TodoKind.task,
    this.deadline,
    this.originalDeadlineDay,
    this.remind = false,
    Set<ReminderAdvance>? reminderAdvances,
    this.vibrationMode = VibrationMode.continuous,
    this.repeatMode = TodoRepeatMode.none,
    this.completed = false,
    this.sortIndex = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        reminderAdvances = reminderAdvances ?? {ReminderAdvance.atTime},
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'kind': kind.name,
    'deadline': deadline?.toIso8601String(),
    'originalDeadlineDay': originalDeadlineDay,
    'remind': remind,
    'reminderAdvances': reminderAdvances.map((e) => e.name).toList(),
    'vibrationMode': vibrationMode.name,
    'repeatMode': repeatMode.name,
    'completed': completed,
    'sortIndex': sortIndex,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Todo.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? const Uuid().v4();
    final title = json['title'] as String? ?? '';
    // 兼容旧格式：单选 reminderAdvance 字段
    Set<ReminderAdvance> advances;
    if (json['reminderAdvances'] != null) {
      advances = (json['reminderAdvances'] as List<dynamic>)
          .map((e) => ReminderAdvance.values.firstWhere(
                (v) => v.name == e,
                orElse: () => ReminderAdvance.atTime,
              ))
          .toSet();
    } else if (json['reminderAdvance'] != null) {
      advances = {
        ReminderAdvance.values.firstWhere(
          (v) => v.name == json['reminderAdvance'],
          orElse: () => ReminderAdvance.atTime,
        )
      };
    } else {
      advances = {ReminderAdvance.atTime};
    }
    return Todo(
      id: id,
      title: title,
      description: json['description'] as String? ?? '',
      kind: TodoKind.values.firstWhere(
        (v) => v.name == (json['kind'] as String?),
        orElse: () => TodoKind.task,
      ),
      deadline: json['deadline'] != null
          ? DateTime.tryParse(json['deadline'] as String)
          : null,
      originalDeadlineDay: json['originalDeadlineDay'] as int? ??
          (json['deadline'] != null ? DateTime.tryParse(json['deadline'] as String)?.day : null),
      remind: json['remind'] as bool? ?? false,
      reminderAdvances: advances,
      vibrationMode: VibrationMode.values.firstWhere(
        (v) => v.name == (json['vibrationMode'] as String?),
        orElse: () => VibrationMode.continuous,
      ),
      repeatMode: TodoRepeatMode.values.firstWhere(
        (v) => v.name == (json['repeatMode'] as String?),
        orElse: () => TodoRepeatMode.none,
      ),
      completed: json['completed'] as bool? ?? false,
      sortIndex: json['sortIndex'] as int? ?? 0,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Todo copyWith({
    String? title,
    String? description,
    TodoKind? kind,
    Object? deadline = _sentinel,
    int? originalDeadlineDay,
    bool? remind,
    Set<ReminderAdvance>? reminderAdvances,
    VibrationMode? vibrationMode,
    TodoRepeatMode? repeatMode,
    bool? completed,
    int? sortIndex,
    DateTime? updatedAt,
  }) => Todo(
    id: id,
    title: title ?? this.title,
    description: description ?? this.description,
    kind: kind ?? this.kind,
    deadline: deadline == _sentinel ? this.deadline : deadline as DateTime?,
    originalDeadlineDay: originalDeadlineDay ?? this.originalDeadlineDay,
    remind: remind ?? this.remind,
    reminderAdvances: reminderAdvances ?? this.reminderAdvances,
    vibrationMode: vibrationMode ?? this.vibrationMode,
    repeatMode: repeatMode ?? this.repeatMode,
    completed: completed ?? this.completed,
    sortIndex: sortIndex ?? this.sortIndex,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// 同步文件的顶层结构
class TodoFile {
  static const int currentVersion = 1;
  final int version;
  DateTime updatedAt;
  List<Todo> todos;

  TodoFile({
    this.version = currentVersion,
    DateTime? updatedAt,
    List<Todo>? todos,
  })  : updatedAt = updatedAt ?? DateTime.now(),
        todos = todos ?? [];

  Map<String, dynamic> toJson() => {
    'version': version,
    'updatedAt': updatedAt.toIso8601String(),
    'todos': todos.map((t) => t.toJson()).toList(),
  };

  factory TodoFile.fromJson(Map<String, dynamic> json) {
    final rawTodos = (json['todos'] is List) ? json['todos'] as List<dynamic> : <dynamic>[];
    final todos = <Todo>[];
    for (final e in rawTodos) {
      try {
        todos.add(Todo.fromJson(e as Map<String, dynamic>));
      } catch (err) {
        // 单条解析失败不影响其他 todo
        debugPrint('Todo 解析失败，已跳过: $err');
      }
    }
    return TodoFile(
      version: json['version'] as int? ?? 1,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
      todos: todos,
    );
  }
}
