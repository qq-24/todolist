import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../models/todo.dart';

/// 本地 JSON 文件读写服务
class LocalStorageService {
  static const _fileName = 'todos.json';
  String? _cachedPath;

  Future<String> get _filePath async {
    if (_cachedPath != null) return _cachedPath!;
    final dir = await getApplicationSupportDirectory();
    if (!await dir.exists()) await dir.create(recursive: true);
    final newPath = '${dir.path}/$_fileName';

    // 数据迁移：从旧路径（Documents 根目录）迁移到新路径
    if (!File(newPath).existsSync()) {
      try {
        final oldDir = await getApplicationDocumentsDirectory();
        final oldFile = File('${oldDir.path}/$_fileName');
        if (await oldFile.exists()) {
          await oldFile.copy(newPath);
          await oldFile.delete();
        }
      } on Exception catch (e) {
        // 迁移失败不阻塞启动，旧数据保留在原位，下次还会重试
        print('数据迁移失败: $e');
      }
    }

    _cachedPath = newPath;
    return newPath;
  }

  /// 加载本地数据，文件不存在或解析失败返回 null
  Future<TodoFile?> load() async {
    try {
      final file = File(await _filePath);
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      if (content.trim().isEmpty) return null;
      return TodoFile.fromJson(jsonDecode(content) as Map<String, dynamic>);
    } on Exception catch (e) {
      // 文件损坏、权限不足、JSON 解析失败等，记录日志返回 null
      print('本地数据加载失败: $e');
      return null;
    }
  }

  /// 保存数据到本地（原子写入：先写临时文件再 rename）
  Future<void> save(TodoFile data) async {
    final path = await _filePath;
    final tempPath = '$path.tmp';
    final tempFile = File(tempPath);
    try {
      await tempFile.writeAsString(jsonEncode(data.toJson()));
      await tempFile.rename(path);
    } on Exception {
      // 清理临时文件
      try {
        if (await tempFile.exists()) await tempFile.delete();
      } on Exception {
        // 清理失败不阻塞，忽略（临时文件残留不影响功能）
      }
      rethrow; // 向上传播让调用方处理
    }
  }

  /// 计算数据的 SHA256 哈希，用于防重复推送
  String computeHash(TodoFile data) {
    final content = jsonEncode(data.toJson());
    return sha256.convert(utf8.encode(content)).toString();
  }
}
