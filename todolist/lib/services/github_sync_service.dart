import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/todo.dart';

/// 同步结果
enum SyncResult { success, conflict, noChange, error }

/// fetch 结果：区分"文件不存在"和"请求失败"
class FetchResult {
  final TodoFile? data;
  final String? sha;
  final bool notFound; // true = 文件不存在（404），false = 正常或失败
  final bool failed; // true = 请求失败（网络错误、非200/404状态码）

  const FetchResult({this.data, this.sha, this.notFound = false, this.failed = false});

  factory FetchResult.success(TodoFile data, String sha) =>
      FetchResult(data: data, sha: sha);
  factory FetchResult.fileNotFound() =>
      const FetchResult(notFound: true);
  factory FetchResult.failure() =>
      const FetchResult(failed: true);
}

/// GitHub REST API 交互服务
class GithubSyncService {
  String? _lastSha;

  String? get lastSha => _lastSha;

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $githubToken',
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
  };

  String get _apiUrl =>
      'https://api.github.com/repos/$githubOwner/$githubRepo/contents/$githubFilePath';

  /// 拉取远端数据
  Future<FetchResult> fetch() async {
    try {
      final response = await http.get(
        Uri.parse(_apiUrl),
        headers: _headers,
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final sha = body['sha'] as String;
        final contentBase64 = (body['content'] as String).replaceAll('\n', '');
        final content = utf8.decode(base64Decode(contentBase64));
        final todoFile =
            TodoFile.fromJson(jsonDecode(content) as Map<String, dynamic>);
        _lastSha = sha;
        return FetchResult.success(todoFile, sha);
      } else if (response.statusCode == 404) {
        _lastSha = null;
        return FetchResult.fileNotFound();
      } else {
        print('GitHub fetch 失败: ${response.statusCode} ${response.body}');
        return FetchResult.failure();
      }
    } on Exception catch (e) {
      print('GitHub fetch 异常: $e');
      return FetchResult.failure();
    }
  }

  /// 推送数据到远端
  Future<SyncResult> push(TodoFile data, {String? sha}) async {
    try {
      final content = base64Encode(utf8.encode(
          const JsonEncoder.withIndent('  ').convert(data.toJson())));
      final body = <String, dynamic>{
        'message': '同步 todos ${DateTime.now().toIso8601String()}',
        'content': content,
      };
      if (sha != null) {
        body['sha'] = sha;
      }

      final response = await http.put(
        Uri.parse(_apiUrl),
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final respBody = jsonDecode(response.body) as Map<String, dynamic>;
        _lastSha =
            (respBody['content'] as Map<String, dynamic>?)?['sha'] as String?;
        return SyncResult.success;
      } else if (response.statusCode == 409) {
        return SyncResult.conflict;
      } else {
        print('GitHub push 失败: ${response.statusCode} ${response.body}');
        return SyncResult.error;
      }
    } on Exception catch (e) {
      print('GitHub push 异常: $e');
      return SyncResult.error;
    }
  }
}
