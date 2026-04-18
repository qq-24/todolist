import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config.dart' show githubFilePath;
import '../models/todo.dart';

/// 同步结果
class SyncResult {
  final SyncResultType type;
  final String? errorMessage;
  const SyncResult(this.type, {this.errorMessage});

  static SyncResult success = const SyncResult(SyncResultType.success);
  static SyncResult conflict = const SyncResult(SyncResultType.conflict);
  static SyncResult noChange = const SyncResult(SyncResultType.noChange);
  static SyncResult error([String? message]) => SyncResult(SyncResultType.error, errorMessage: message);
}

enum SyncResultType { success, conflict, noChange, error }

/// fetch 结果：区分"文件不存在"和"请求失败"
class FetchResult {
  final TodoFile? data;
  final String? sha;
  final bool notFound;
  final bool failed;
  final String? errorMessage;

  const FetchResult({this.data, this.sha, this.notFound = false, this.failed = false, this.errorMessage});

  factory FetchResult.success(TodoFile data, String sha) =>
      FetchResult(data: data, sha: sha);
  factory FetchResult.fileNotFound() =>
      const FetchResult(notFound: true);
  factory FetchResult.failure([String? message]) =>
      FetchResult(failed: true, errorMessage: message);
}

/// GitHub REST API 交互服务
class GithubSyncService {
  String _token = '';
  String _owner = '';
  String _repo = '';

  void configure({required String token, required String owner, required String repo}) {
    _token = token;
    _owner = owner;
    _repo = repo;
  }

  bool get isConfigured => _token.isNotEmpty && _owner.isNotEmpty && _repo.isNotEmpty;

  String? _lastSha;

  String? get lastSha => _lastSha;

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $_token',
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
  };

  String get _apiUrl =>
      'https://api.github.com/repos/$_owner/$_repo/contents/$githubFilePath';

  /// 拉取远端数据
  Future<FetchResult> fetch() async {
    if (!isConfigured) return FetchResult.failure('GitHub not configured');
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
        return FetchResult.failure(_errorMessage(response));
      }
    } on Exception catch (e) {
      print('GitHub fetch 异常: $e');
      return FetchResult.failure(_networkErrorMessage(e));
    }
  }

  /// 推送数据到远端
  Future<SyncResult> push(TodoFile data, {String? sha}) async {
    if (!isConfigured) return SyncResult.error('GitHub not configured');
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
        return SyncResult.error(_errorMessage(response));
      }
    } on Exception catch (e) {
      print('GitHub push 异常: $e');
      return SyncResult.error(_networkErrorMessage(e));
    }
  }

  String _errorMessage(http.Response response) {
    return switch (response.statusCode) {
      401 => '认证失败',
      403 => '权限不足',
      >= 500 => '服务器错误',
      _ => 'HTTP ${response.statusCode}',
    };
  }

  /// 根据异常类型返回用户可理解的错误描述
  String _networkErrorMessage(Object e) {
    if (e is TimeoutException) return '网络超时';
    if (e is SocketException) {
      final msg = e.message.toLowerCase();
      if (msg.contains('no address') || msg.contains('host')) return 'DNS解析失败';
      if (msg.contains('connection refused')) return '连接被拒绝';
      if (msg.contains('network is unreachable') || msg.contains('no route')) return '无网络连接';
      return '网络不可用: ${e.message}';
    }
    if (e is HandshakeException || e is TlsException) return 'SSL证书错误';
    if (e is HttpException) return 'HTTP协议错误';
    return '网络错误: $e';
  }
}

