import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:launch_at_startup/launch_at_startup.dart' as las;
import 'package:shared_preferences/shared_preferences.dart';

/// 排序方式
enum SortMode { manual, byDeadline, byCreatedTime }

/// 设置状态管理
class SettingsProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  SortMode _sortMode = SortMode.manual;
  bool _vibrateInDnd = true;
  bool _launchAtStartup = true;
  String _hotkey = 'alt+t';
  String _addTaskKey = 'space';
  String _githubToken = '';
  String _githubOwner = '';
  String _githubRepo = '';

  ThemeMode get themeMode => _themeMode;
  SortMode get sortMode => _sortMode;
  bool get vibrateInDnd => _vibrateInDnd;
  bool get launchAtStartup => _launchAtStartup;
  String get hotkey => _hotkey;
  String get addTaskKey => _addTaskKey;
  String get githubToken => _githubToken;
  String get githubOwner => _githubOwner;
  String get githubRepo => _githubRepo;
  bool get isGithubConfigured => _githubToken.isNotEmpty && _githubOwner.isNotEmpty && _githubRepo.isNotEmpty;

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
    _launchAtStartup = prefs.getBool('launch_at_startup') ?? true;
    _hotkey = prefs.getString('hotkey') ?? 'alt+t';
    _addTaskKey = prefs.getString('add_task_key') ?? 'space';
    if (_addTaskKey != 'space' && _addTaskKey != 'enter') _addTaskKey = 'space';
    _githubToken = prefs.getString('github_token') ?? '';
    _githubOwner = prefs.getString('github_owner') ?? '';
    _githubRepo = prefs.getString('github_repo') ?? '';

    // Windows: 初始化开机自启并同步注册表
    if (Platform.isWindows) {
      las.launchAtStartup.setup(
        appName: 'todolist',
        appPath: Platform.resolvedExecutable,
        args: ['--minimized'],
      );
      try {
        if (_launchAtStartup) {
          await las.launchAtStartup.enable();
        } else {
          await las.launchAtStartup.disable();
        }
      } on Exception catch (e) {
        debugPrint('开机自启注册表操作失败: $e');
      }
    }
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

  Future<void> setLaunchAtStartup(bool value) async {
    _launchAtStartup = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('launch_at_startup', value);
    if (Platform.isWindows) {
      try {
        if (value) {
          await las.launchAtStartup.enable();
        } else {
          await las.launchAtStartup.disable();
        }
      } on Exception catch (e) {
        debugPrint('开机自启注册表操作失败: $e');
        // 回滚
        _launchAtStartup = !value;
        notifyListeners();
        await prefs.setBool('launch_at_startup', !value);
      }
    }
  }

  Future<void> setHotkey(String value) async {
    _hotkey = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('hotkey', value);
  }

  Future<void> setAddTaskKey(String value) async {
    if (value != 'space' && value != 'enter') return;
    _addTaskKey = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('add_task_key', value);
  }

  Future<void> setGithubConfig({required String token, required String owner, required String repo}) async {
    _githubToken = token;
    _githubOwner = owner;
    _githubRepo = repo;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('github_token', token);
    await prefs.setString('github_owner', owner);
    await prefs.setString('github_repo', repo);
  }
}
