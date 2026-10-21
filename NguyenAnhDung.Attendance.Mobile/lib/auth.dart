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
    final icon = register
        ? Icons.person_add_alt_1_rounded
        : verify
        ? Icons.mark_email_read_outlined
        : otp
        ? Icons.shield_outlined
        : Icons.waving_hand_outlined;
    return Scaffold(
      body: Stack(
        children: [
          Container(
            height: 300,
            decoration: const BoxDecoration(
              gradient: brandGradient,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(36)),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const BrandLogo(size: 52),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Chấm công',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 23,
                                  ),
                                ),
                                Text(
                                  'HỮU DUYÊN',
                                  style: TextStyle(
                                    fontSize: 11,
                                    letterSpacing: 2,
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton.filledTonal(
                            tooltip: 'Cấu hình API',
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.white24,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: busy
                                ? null
                                : () => apiSettings(context, widget.session),
                            icon: const Icon(Icons.settings_outlined),
                          ),
                        ],
                      ),
                      const SizedBox(height: 36),
                      Container(
                        padding: const EdgeInsets.fromLTRB(22, 24, 22, 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x1A14213D),
                              blurRadius: 30,
                              offset: Offset(0, 14),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                IconBadge(icon),
                                const Spacer(),
                                if (mode == 'login' || otp)
                                  _LoginSteps(otp: otp),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              title,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: brandInk,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              otp
                                  ? 'Nhập mã gửi đến ${challenge?['maskedEmail']}. Hết hạn: ${localTime(challenge?['expiresAtUtc'])} (UTC+7).'
                                  : verify
                                  ? 'Mã xác thực được gửi đến email của bạn.'
                                  : register
                                  ? 'Đăng ký bằng email, xác thực mã để kích hoạt tài khoản.'
                                  : 'Quản lý thời gian, kết nối đội ngũ.',
                              style: const TextStyle(
                                color: brandMuted,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 24),
                            if (widget.session.notice != null &&
                                mode == 'login')
                              _Banner(
                                widget.session.notice!,
                                Colors.deepOrange,
                                Icons.info_outline,
                              ),
                            _form(context, register, verify, otp),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Nhóm Hữu Duyên • Ứng dụng chấm công nhân viên',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: brandMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _form(BuildContext context, bool register, bool verify, bool otp) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 10,
                            ),
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
                          _Banner(
                            error!,
                            Theme.of(context).colorScheme.error,
                            Icons.error_outline,
                          ),
                        if (info != null)
                          _Banner(info!, Colors.teal, Icons.check_circle_outline),
                        SizedBox(
                          width: double.infinity,
                          height: 54,
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
                    TextButton.icon(
                      onPressed: busy ? null : () => change('login'),
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: const Text('Quay lại đăng nhập'),
                    ),
        ],
      );
}

class _LoginSteps extends StatelessWidget {
  final bool otp;
  const _LoginSteps({required this.otp});
  @override
  Widget build(BuildContext context) {
    Widget dot(String number, String label, bool active, bool done) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 11,
          backgroundColor: active || done ? brandPrimary : borderColor,
          child: done
              ? const Icon(Icons.check, size: 14, color: Colors.white)
              : Text(
                  number,
                  style: TextStyle(
                    fontSize: 11,
                    color: active ? Colors.white : brandMuted,
                  ),
                ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: active ? brandInk : brandMuted,
          ),
        ),
      ],
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot('1', 'Mật khẩu', !otp, otp),
        Container(
          width: 16,
          height: 2,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          color: otp ? brandPrimary : borderColor,
        ),
        dot('2', 'OTP', otp, false),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;
  const _Banner(this.text, this.color, this.icon);
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: .25)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: TextStyle(color: color, height: 1.35)),
        ),
      ],
    ),
  );
}
