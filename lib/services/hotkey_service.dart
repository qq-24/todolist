import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

/// Windows 全局快捷键服务
class HotkeyService {
  final Future<void> Function() onToggle;

  HotkeyService(this.onToggle);

  HotKey? _currentHotKey;

  Future<void> init(String hotkeyStr) async {
    try {
      final hotKey = parseHotkey(hotkeyStr);
      if (hotKey != null) {
        _currentHotKey = hotKey;
        await hotKeyManager.register(hotKey, keyDownHandler: (_) => onToggle());
      }
    } on Exception catch (e) {
      debugPrint('注册全局热键失败: $e');
    }
  }

  Future<void> updateHotkey(String newHotkeyStr) async {
    try {
      if (_currentHotKey != null) {
        await hotKeyManager.unregister(_currentHotKey!);
        _currentHotKey = null;
      }
      final hotKey = parseHotkey(newHotkeyStr);
      if (hotKey != null) {
        _currentHotKey = hotKey;
        await hotKeyManager.register(hotKey, keyDownHandler: (_) => onToggle());
      }
    } on Exception catch (e) {
      debugPrint('更新全局热键失败: $e');
    }
  }

  Future<void> dispose() async {
    try {
      if (_currentHotKey != null) {
        await hotKeyManager.unregister(_currentHotKey!);
        _currentHotKey = null;
      }
    } on Exception catch (e) {
      debugPrint('注销全局热键失败: $e');
    }
  }

  /// 将字符串（如 "alt+t"）解析为 HotKey 对象
  static HotKey? parseHotkey(String str) {
    final parts = str.toLowerCase().split('+').map((s) => s.trim()).toList();
    if (parts.isEmpty) return null;

    final keyStr = parts.last;
    final modifierStrs = parts.sublist(0, parts.length - 1);

    // 解析 modifier
    final modifiers = <HotKeyModifier>[];
    for (final m in modifierStrs) {
      final mod = switch (m) {
        'alt' => HotKeyModifier.alt,
        'ctrl' || 'control' => HotKeyModifier.control,
        'shift' => HotKeyModifier.shift,
        'meta' || 'win' => HotKeyModifier.meta,
        _ => null,
      };
      if (mod == null) return null;
      modifiers.add(mod);
    }
    if (modifiers.isEmpty) return null; // 必须有至少一个 modifier

    // 解析主键
    final logicalKey = _parseKey(keyStr);
    if (logicalKey == null) return null;

    return HotKey(
      key: logicalKey,
      modifiers: modifiers,
      scope: HotKeyScope.system,
    );
  }

  /// 支持字母 a-z、数字 0-9
  static LogicalKeyboardKey? _parseKey(String key) {
    if (key.length == 1) {
      final c = key.codeUnitAt(0);
      // a-z
      if (c >= 0x61 && c <= 0x7a) {
        return LogicalKeyboardKey(c - 0x61 + LogicalKeyboardKey.keyA.keyId);
      }
      // 0-9
      if (c >= 0x30 && c <= 0x39) {
        return LogicalKeyboardKey(c - 0x30 + LogicalKeyboardKey.digit0.keyId);
      }
    }
    return null;
  }

  /// 从 LogicalKeyboardKey 提取单字符标签（a-z, 0-9），不依赖 debugName
  static String? _keyToChar(LogicalKeyboardKey key) {
    final id = key.keyId;
    final aId = LogicalKeyboardKey.keyA.keyId;
    final zId = LogicalKeyboardKey.keyZ.keyId;
    final d0Id = LogicalKeyboardKey.digit0.keyId;
    final d9Id = LogicalKeyboardKey.digit9.keyId;
    if (id >= aId && id <= zId) {
      return String.fromCharCode(0x61 + (id - aId)); // a-z
    }
    if (id >= d0Id && id <= d9Id) {
      return String.fromCharCode(0x30 + (id - d0Id)); // 0-9
    }
    return null;
  }

  /// 将快捷键字符串格式化为显示文本（如 "alt+t" → "Alt + T"）
  static String formatForDisplay(String str) {
    return str.split('+').map((s) {
      final t = s.trim();
      if (t.isEmpty) return t;
      return t[0].toUpperCase() + t.substring(1);
    }).join(' + ');
  }

  /// 将 HotKey 对象序列化为存储字符串（如 "alt+t"）
  /// 仅支持字母和数字主键，不支持的返回 null
  static String? hotkeyToString(HotKey hotKey) {
    final parts = <String>[];
    for (final m in hotKey.modifiers ?? <HotKeyModifier>[]) {
      parts.add(m.name);
    }
    final keyChar = _keyToChar(hotKey.logicalKey);
    if (keyChar == null) return null;
    parts.add(keyChar);
    return parts.join('+');
  }
}
