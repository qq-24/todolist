import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'providers/settings_provider.dart';
import 'providers/todo_provider.dart';
import 'screens/home_screen.dart';
import 'services/windows_notification_service.dart';
import 'services/windows_tray_service.dart';
import 'services/hotkey_service.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  final settings = SettingsProvider();
  await settings.init();

  final todoProvider = TodoProvider(settings);

  // Windows: 窗口管理 + 托盘 + 通知
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);

    // 恢复窗口位置和大小
    final prefs = await SharedPreferences.getInstance();
    final wx = prefs.getDouble('window_x');
    final wy = prefs.getDouble('window_y');
    final ww = prefs.getDouble('window_w');
    final wh = prefs.getDouble('window_h');
    if (ww != null && wh != null) {
      await windowManager.setSize(Size(ww, wh));
    }
    if (wx != null && wy != null) {
      await windowManager.setPosition(Offset(wx, wy));
    }

    final startMinimized = args.contains('--minimized');
    if (startMinimized) {
      await windowManager.hide();
    }

    // 通知服务
    final winNotifier = WindowsNotificationService(todoProvider);
    await winNotifier.init();
    todoProvider.reminder.setWindowsNotifier(winNotifier);

    // 托盘服务
    final trayService = WindowsTrayService(todoProvider, settings);
    await trayService.init();

    // 全局快捷键服务
    final hotkeyService = HotkeyService(() async {
      try {
        if (await windowManager.isVisible()) {
          await windowManager.hide();
        } else {
          await windowManager.show();
          await windowManager.focus();
        }
      } on Exception catch (e) {
        debugPrint('快捷键 toggle 窗口失败: $e');
      }
    });
    await hotkeyService.init(settings.hotkey);
    // 监听快捷键设置变化
    String lastHotkey = settings.hotkey;
    settings.addListener(() {
      if (settings.hotkey != lastHotkey) {
        lastHotkey = settings.hotkey;
        hotkeyService.updateHotkey(lastHotkey);
      }
    });
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: todoProvider),
      ],
      child: const TodoApp(),
    ),
  );

  todoProvider.init();
}

class TodoApp extends StatelessWidget {
  const TodoApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    final lightScheme = ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: Brightness.light,
    );
    final darkScheme = ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: Brightness.dark,
    );

    return MaterialApp(
      title: 'Todo',
      debugShowCheckedModeBanner: false,
      // 中文本地化
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      themeMode: settings.themeMode,
      theme: ThemeData(
        colorScheme: lightScheme,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: darkScheme,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
      builder: (context, child) {
        if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(0.92),
            ),
            child: child!,
          );
        }
        return child!;
      },
    );
  }
}
