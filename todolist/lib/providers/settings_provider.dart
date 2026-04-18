import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 排序方式
enum SortMode { manual, byDeadline }

/// 设置状态管理
class SettingsProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  SortMode _sortMode = SortMode.manual;
  bool _vibrateInDnd = true;

  ThemeMode get themeMode => _themeMode;
  SortMode get sortMode => _sortMode;
  bool get vibrateInDnd => _vibrateInDnd;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt('themeMode') ?? 0;
    _themeMode = (themeIndex >= 0 && themeIndex < ThemeMode.values.length)
        ? ThemeMode.values[themeIndex]
        : ThemeMode.system;
    final sortIndex = prefs.getInt('sortMode') ?? 0;
    _sortMode = (sortIndex >= 0 && sortIndex < SortMode.values.length)
        ? SortMode.values[sortIndex]
        : SortMode.manual;
    _vibrateInDnd = prefs.getBool('vibrate_in_dnd') ?? true;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('themeMode', mode.index);
  }

  Future<void> setSortMode(SortMode mode) async {
    _sortMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('sortMode', mode.index);
  }

  Future<void> setVibrateInDnd(bool value) async {
    _vibrateInDnd = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('vibrate_in_dnd', value);
  }
}
