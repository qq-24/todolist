import 'package:uuid/uuid.dart';

/// 用于 copyWith 中区分"未传参"和"显式传 null"的哨兵值
const Object _sentinel = Object();

/// 震动模式
enum VibrationMode {
  continuous, // 持续震动（每 5.5 秒重复，60 秒后停止）
  once;       // 仅震动一轮

  String get label => switch (this) {
    continuous => '持续震动',
    once => '震动一次',
  };
}

/// 提醒提前量
enum ReminderAdvance {
  atTime, // 到期时
  min15, // 提前15分钟
  hour1, // 提前1小时
  day1; // 提前1天

  /// 转换为 Duration 偏移量
  Duration get offset => switch (this) {
    atTime => Duration.zero,
    min15 => const Duration(minutes: 15),
    hour1 => const Duration(hours: 1),
    day1 => const Duration(days: 1),
  };

  String get label => switch (this) {
    atTime => '到期时',
    min15 => '15分钟前',
    hour1 => '1小时前',
    day1 => '1天前',
  };
}

class Todo {
  final String id;
  String title;
  String description;
  DateTime? deadline;
  bool remind;
  Set<ReminderAdvance> reminderAdvances; // 多选提前量
  VibrationMode vibrationMode;
  bool completed;
  int sortIndex;
  final DateTime createdAt;
  DateTime updatedAt;

  Todo({
    String? id,
    required this.title,
    this.description = '',
    this.deadline,
    this.remind = false,
    Set<ReminderAdvance>? reminderAdvances,
    this.vibrationMode = VibrationMode.continuous,
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
    'deadline': deadline?.toIso8601String(),
    'remind': remind,
    'reminderAdvances': reminderAdvances.map((e) => e.name).toList(),
    'vibrationMode': vibrationMode.name,
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
      deadline: json['deadline'] != null
          ? DateTime.tryParse(json['deadline'] as String)
          : null,
      remind: json['remind'] as bool? ?? false,
      reminderAdvances: advances,
      vibrationMode: VibrationMode.values.firstWhere(
        (v) => v.name == (json['vibrationMode'] as String?),
        orElse: () => VibrationMode.continuous,
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
    Object? deadline = _sentinel,
    bool? remind,
    Set<ReminderAdvance>? reminderAdvances,
    VibrationMode? vibrationMode,
    bool? completed,
    int? sortIndex,
    DateTime? updatedAt,
  }) => Todo(
    id: id,
    title: title ?? this.title,
    description: description ?? this.description,
    deadline: deadline == _sentinel ? this.deadline : deadline as DateTime?,
    remind: remind ?? this.remind,
    reminderAdvances: reminderAdvances ?? this.reminderAdvances,
    vibrationMode: vibrationMode ?? this.vibrationMode,
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

  factory TodoFile.fromJson(Map<String, dynamic> json) => TodoFile(
    version: json['version'] as int? ?? 1,
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
    todos: (json['todos'] as List<dynamic>?)
            ?.map((e) => Todo.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
  );
}
