import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

typedef Json = Map<String, dynamic>;
const defaultBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:5080/api',
);

class ApiException implements Exception {
  final String message;
  final int? status;
  const ApiException(this.message, [this.status]);
  @override
  String toString() => message;
}

class Session extends ChangeNotifier {
  final FlutterSecureStorage storage;
  final http.Client client;
  Session({FlutterSecureStorage? storage, http.Client? client})
    : storage = storage ?? const FlutterSecureStorage(),
      client = client ?? http.Client();
  String baseUrl = defaultBaseUrl;
  String? token;
  Json? user;
  bool loading = true;
  String? notice;
  bool get admin => user?['role'] == 'Admin';
  bool get manager => admin || user?['role'] == 'Manager';
  Future<void> restore() async {
    try {
      baseUrl = await storage.read(key: 'apiBaseUrl') ?? defaultBaseUrl;
      token = await storage.read(key: 'accessToken');
      if (token != null) user = await request('GET', '/auth/me') as Json;
    } catch (e) {
      notice = 'Không khôi phục được phiên: $e';
      token = null;
      user = null;
      await storage.delete(key: 'accessToken');
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> changeBaseUrl(String value) async {
    final normalized = value.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        !uri.path.endsWith('/api')) {
      throw const ApiException('URL phải có dạng http(s)://máy-chủ:5080/api');
    }
    baseUrl = normalized;
    await storage.write(key: 'apiBaseUrl', value: baseUrl);
  }

  Future<void> accept(Json result) async {
    token = result['accessToken'] as String;
    await storage.write(key: 'accessToken', value: token);
    user = result['user'] as Json;
    notice = null;
    notifyListeners();
  }

  Future<void> logout({String? message}) async {
    token = null;
    user = null;
    notice = message;
    await storage.delete(key: 'accessToken');
    notifyListeners();
  }

  Future<dynamic> request(String method, String path, [Json? body]) async {
    final request = http.Request(method, Uri.parse('$baseUrl$path'));
    request.headers['Content-Type'] = 'application/json';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) request.body = jsonEncode(body);
    try {
      final streamed = await client
          .send(request)
          .timeout(const Duration(seconds: 25));
      final response = await http.Response.fromStream(streamed)
          .timeout(const Duration(seconds: 25));
      dynamic decoded;
      try {
        decoded = response.body.isEmpty ? null : jsonDecode(response.body);
      } catch (_) {
        decoded = null;
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return decoded;
      }
      final message = decoded is Map && decoded['message'] != null
          ? decoded['message'].toString()
          : 'Yêu cầu thất bại (${response.statusCode}). Kiểm tra API và dữ liệu.';
      if (response.statusCode == 401 && token != null) {
        await logout(message: 'Phiên đã hết hạn. Vui lòng đăng nhập lại.');
      }
      throw ApiException(message, response.statusCode);
    } on TimeoutException {
      throw const ApiException(
        'Máy chủ phản hồi quá lâu. Kiểm tra mạng và URL API.',
      );
    } on SocketException {
      throw const ApiException(
        'Không kết nối được máy chủ. Kiểm tra Wi-Fi, URL API và firewall.',
      );
    } on http.ClientException {
      throw const ApiException(
        'Không kết nối được API. Kiểm tra địa chỉ máy chủ.',
      );
    }
  }

  @override
  void dispose() {
    client.close();
    super.dispose();
  }
}

String roleLabel(dynamic role) => switch (role) {
  'Admin' => 'Quản trị viên',
  'Manager' => 'Quản lý',
  _ => 'Nhân viên',
};
String dateOnly(DateTime date) => DateFormat('yyyy-MM-dd').format(date);
DateTime businessNow() => DateTime.now().toUtc().add(const Duration(hours: 7));
String localTime(dynamic value, {bool date = false}) {
  if (value == null) return '—';
  final parsed = DateTime.tryParse(value.toString());
  if (parsed == null) return value.toString();
  return DateFormat(date ? 'dd/MM/yyyy • HH:mm' : 'HH:mm')
      .format(parsed.toUtc().add(const Duration(hours: 7)));
}

String displayDate(dynamic value) {
  final date = DateTime.tryParse('$value');
  return date == null ? '$value' : DateFormat('dd/MM/yyyy').format(date);
}

String leaveLabel(dynamic type) => switch (type) {
  'Annual' => 'Nghỉ phép',
  'Sick' => 'Nghỉ ốm',
  'Unpaid' => 'Nghỉ không lương',
  'Correction' => 'Bổ sung chấm công',
  _ => '$type',
};
String statusLabel(dynamic status) => switch (status) {
  'Pending' => 'Chờ duyệt',
  'Approved' => 'Đã duyệt',
  'Rejected' => 'Từ chối',
  _ => '$status',
};
void showMessage(BuildContext context, Object message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('$message'), behavior: SnackBarBehavior.floating),
  );
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    ) ??
    false;

class ErrorPanel extends StatelessWidget {
  final Object error;
  final VoidCallback retry;
  const ErrorPanel({super.key, required this.error, required this.retry});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 48, color: Colors.blueGrey),
          const SizedBox(height: 12),
          Text('$error', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: retry,
            icon: const Icon(Icons.refresh),
            label: const Text('Thử lại'),
          ),
        ],
      ),
    ),
  );
}

class EmptyPanel extends StatelessWidget {
  final String message;
  const EmptyPanel(this.message, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inbox_outlined, size: 46, color: Colors.blueGrey),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

class DataPage extends StatefulWidget {
  final Future<dynamic> Function() load;
  final Widget Function(BuildContext, dynamic, VoidCallback) builder;
  const DataPage({super.key, required this.load, required this.builder});
  @override
  State<DataPage> createState() => _DataPageState();
}

class _DataPageState extends State<DataPage> {
  late Future<dynamic> future;
  @override
  void initState() {
    super.initState();
    future = widget.load();
  }

  void reload() {
    if (mounted) {
      setState(() {
        future = widget.load();
      });
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<dynamic>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return ErrorPanel(error: snapshot.error!, retry: reload);
      }
      return widget.builder(context, snapshot.data, reload);
    },
  );
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  const SectionTitle(this.title, {super.key, this.subtitle, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    subtitle!,
                    style: const TextStyle(color: Colors.blueGrey),
                  ),
                ),
            ],
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class StatusPill extends StatelessWidget {
  final String text;
  final Color color;
  const StatusPill(
    this.text, {
    super.key,
    this.color = const Color(0xFF2455D6),
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );
}
