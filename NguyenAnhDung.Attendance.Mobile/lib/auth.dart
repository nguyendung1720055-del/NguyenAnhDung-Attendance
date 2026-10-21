import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core.dart';

Future<void> apiSettings(BuildContext context, Session session) async {
  final controller = TextEditingController(text: session.baseUrl);
  String? error;
  bool busy = false;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: const Text('Kết nối máy chủ'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Android giả lập: 10.0.2.2. Điện thoại thật: IP LAN của máy chạy API. Hai thiết bị cần cùng mạng.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: 'API URL',
                  helperText: 'Ví dụ: http://192.168.1.20:5080/api',
                  errorText: error,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    update(() {
                      busy = true;
                      error = null;
                    });
                    try {
                      await session.changeBaseUrl(controller.text);
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      update(() {
                        error = '$e';
                        busy = false;
                      });
                    }
                  },
            child: const Text('Lưu cấu hình'),
          ),
        ],
      ),
    ),
  );
  controller.dispose();
}

class AuthScreen extends StatefulWidget {
  final Session session;
  const AuthScreen({super.key, required this.session});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final form = GlobalKey<FormState>();
  final identifier = TextEditingController();
  final email = TextEditingController();
  final fullName = TextEditingController();
  final password = TextEditingController();
  final code = TextEditingController();
  String mode = 'login';
  Json? challenge;
  String? error;
  String? info;
  bool busy = false;
  bool hide = true;
  @override
  void dispose() {
    for (final c in [identifier, email, fullName, password, code]) {
      c.dispose();
    }
    super.dispose();
  }

  void change(String next) {
    setState(() {
      mode = next;
      error = null;
      info = null;
      code.clear();
    });
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
      info = null;
    });
    try {
      final api = widget.session;
      switch (mode) {
        case 'register':
          final result = await api.request('POST', '/auth/register', {
            'username': identifier.text.trim(),
            'email': email.text.trim(),
            'fullName': fullName.text.trim(),
            'password': password.text,
          });
          if (!mounted) return;
          setState(() {
            mode = 'verify';
            info = result['message']?.toString() ?? 'Đã gửi mã xác thực email.';
            password.clear();
          });
        case 'verify':
          final result = await api.request('POST', '/auth/verify-email', {
            'email': email.text.trim(),
            'code': code.text.trim(),
          });
          if (!mounted) return;
          setState(() {
            mode = 'login';
            code.clear();
            info =
                result['message']?.toString() ??
                'Email đã được xác thực. Hãy đăng nhập.';
          });
        case 'otp':
          final result = await api.request('POST', '/auth/verify-otp', {
            'challengeId': challenge!['challengeId'],
            'code': code.text.trim(),
          });
          await api.accept(result as Json);
          password.clear();
          code.clear();
        default:
          final result = await api.request('POST', '/auth/login', {
            'identifier': identifier.text.trim(),
            'password': password.text,
          });
          if (!mounted) return;
          setState(() {
            challenge = result as Json;
            mode = 'otp';
            password.clear();
            code.clear();
          });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
      }
    }
  }

  Future<void> resend() async {
    if (!email.text.contains('@')) {
      setState(() {
        error = 'Nhập email cần xác thực.';
      });
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.session.request(
        'POST',
        '/auth/resend-verification',
        {'email': email.text.trim()},
      );
      if (mounted) {
        setState(() {
          info = result['message']?.toString();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final register = mode == 'register';
    final verify = mode == 'verify';
    final otp = mode == 'otp';
    final title = register
        ? 'Tạo tài khoản'
        : verify
        ? 'Xác thực email'
        : otp
        ? 'Xác nhận đăng nhập'
        : 'Chào ngày làm việc mới';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.fingerprint,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Chấm công',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 23,
                              ),
                            ),
                            Text(
                              'HỮU DUYÊN',
                              style: TextStyle(
                                fontSize: 11,
                                letterSpacing: 1.4,
                                color: Colors.blueGrey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cấu hình API',
                        onPressed: busy
                            ? null
                            : () => apiSettings(context, widget.session),
                        icon: const Icon(Icons.settings_outlined),
                      ),
                    ],
                  ),
                  const SizedBox(height: 42),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    otp
                        ? 'Nhập mã gửi đến ${challenge?['maskedEmail']}. Hết hạn: ${localTime(challenge?['expiresAtUtc'])} (UTC+7).'
                        : verify
                        ? 'Mã xác thực được gửi đến email của bạn.'
                        : 'Quản lý thời gian, kết nối đội ngũ.',
                    style: const TextStyle(color: Colors.blueGrey),
                  ),
                  const SizedBox(height: 28),
                  if (widget.session.notice != null && mode == 'login')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        widget.session.notice!,
                        style: const TextStyle(color: Colors.deepOrange),
                      ),
                    ),
                  Form(
                    key: form,
                    child: Column(
                      children: [
                        if (!verify && !otp) ...[
                          TextFormField(
                            controller: identifier,
                            enabled: !busy,
                            autofillHints: const [AutofillHints.username],
                            decoration: InputDecoration(
                              labelText: register
                                  ? 'Tên đăng nhập'
                                  : 'Tên đăng nhập hoặc email',
                              prefixIcon: const Icon(Icons.person_outline),
                            ),
                            validator: (v) => v == null || v.trim().isEmpty
                                ? 'Vui lòng nhập tên đăng nhập.'
                                : register &&
                                      !RegExp(r'^[a-zA-Z0-9_.]{3,40}$')
                                          .hasMatch(v.trim())
                                ? 'Dùng 3–40 chữ cái, số, dấu _ hoặc .'
                                : null,
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (register) ...[
                          TextFormField(
                            controller: fullName,
                            enabled: !busy,
                            decoration: const InputDecoration(
                              labelText: 'Họ và tên',
                              prefixIcon: Icon(Icons.badge_outlined),
                            ),
                            validator: (v) => (v?.trim().isEmpty ?? true)
                                ? 'Nhập họ tên.'
                                : null,
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (register || verify) ...[
                          TextFormField(
                            controller: email,
                            enabled: !busy,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                            validator: (v) =>
                                v != null &&
                                    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                        .hasMatch(v.trim())
                                ? null
                                : 'Email không hợp lệ.',
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (!verify && !otp) ...[
                          TextFormField(
                            controller: password,
                            enabled: !busy,
                            obscureText: hide,
                            autofillHints: [
                              register
                                  ? AutofillHints.newPassword
                                  : AutofillHints.password,
                            ],
                            decoration: InputDecoration(
                              labelText: 'Mật khẩu',
                              prefixIcon: const Icon(Icons.lock_outline),
                              helperText: register
                                  ? 'Từ 10 ký tự, có chữ hoa, chữ thường và số'
                                  : null,
                              suffixIcon: IconButton(
                                onPressed: () => setState(() {
                                  hide = !hide;
                                }),
                                icon: Icon(
                                  hide
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return 'Nhập mật khẩu.';
                              }
                              if (register &&
                                  (v.length < 10 ||
                                      !RegExp('[A-Z]').hasMatch(v) ||
                                      !RegExp('[a-z]').hasMatch(v) ||
                                      !RegExp('[0-9]').hasMatch(v))) {
                                return 'Mật khẩu cần 10 ký tự, chữ hoa, thường và số.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (verify || otp) ...[
                          TextFormField(
                            controller: code,
                            enabled: !busy,
                            keyboardType: TextInputType.number,
                            autofillHints: const [AutofillHints.oneTimeCode],
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(6),
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Mã gồm 6 chữ số',
                              prefixIcon: Icon(Icons.password_outlined),
                            ),
                            validator: (v) =>
                                RegExp(r'^\d{6}$').hasMatch(v ?? '')
                                ? null
                                : 'Nhập đủ 6 chữ số.',
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Text(
                              error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        if (info != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Text(
                              info!,
                              style: const TextStyle(color: Colors.teal),
                            ),
                          ),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton(
                            onPressed: busy ? null : submit,
                            child: busy
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    register
                                        ? 'Đăng ký và gửi mã'
                                        : verify
                                        ? 'Xác thực email'
                                        : otp
                                        ? 'Xác nhận OTP'
                                        : 'Tiếp tục đăng nhập',
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (verify)
                    TextButton(
                      onPressed: busy ? null : resend,
                      child: const Text('Gửi lại mã xác thực'),
                    ),
                  if (mode == 'login') ...[
                    TextButton(
                      onPressed: busy ? null : () => change('register'),
                      child: const Text('Chưa có tài khoản? Đăng ký'),
                    ),
                    TextButton(
                      onPressed: busy ? null : () => change('verify'),
                      child: const Text('Đã có mã xác thực email'),
                    ),
                  ],
                  if (mode != 'login')
                    TextButton(
                      onPressed: busy ? null : () => change('login'),
                      child: const Text('Quay lại đăng nhập'),
                    ),
                  const SizedBox(height: 28),
                  const Text(
                    'Nhóm Hữu Duyên',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.blueGrey, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
