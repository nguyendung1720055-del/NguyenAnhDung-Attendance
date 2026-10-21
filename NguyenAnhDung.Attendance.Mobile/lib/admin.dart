import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'core.dart';
import 'attendance.dart';
import 'incidents.dart';

class AdminScreen extends StatelessWidget {
  final Session session;
  const AdminScreen({super.key, required this.session});
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: session.admin ? 5 : 4,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: SectionTitle(
            session.admin ? 'Trang quản trị' : 'Đội ngũ của bạn',
            subtitle: 'Nhân sự, ca làm và thiết lập văn phòng',
            trailing: IconButton(
              tooltip: 'Phát mã QR',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => QrIssueScreen(session: session),
                ),
              ),
              icon: const Icon(Icons.qr_code_2),
            ),
          ),
        ),
        TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            const Tab(text: 'Nhân viên'),
            const Tab(text: 'Phòng ban'),
            const Tab(text: 'Ca làm'),
            if (session.admin) const Tab(text: 'Văn phòng'),
            const Tab(text: 'Sự cố'),
          ],
        ),
        Expanded(
          child: TabBarView(
            children: [
              CatalogScreen(session: session, kind: 'employees'),
              CatalogScreen(session: session, kind: 'departments'),
              CatalogScreen(session: session, kind: 'shifts'),
              if (session.admin) CompanySettings(session: session),
              IncidentsPanel(session: session),
            ],
          ),
        ),
      ],
    ),
  );
}

class CatalogScreen extends StatelessWidget {
  final Session session;
  final String kind;
  const CatalogScreen({super.key, required this.session, required this.kind});
  String get label => switch (kind) {
    'employees' => 'nhân viên',
    'departments' => 'phòng ban',
    _ => 'ca làm',
  };
  Future<void> edit(
    BuildContext context,
    VoidCallback reload, [
    Json? existing,
  ]) async {
    await showDialog<void>(
      context: context,
      builder: (_) =>
          RecordEditor(session: session, kind: kind, existing: existing),
    );
    reload();
  }

  @override
  Widget build(BuildContext context) => DataPage(
    load: () => session.request('GET', '/$kind'),
    builder: (context, data, reload) {
      final records = (data as List).cast<Json>();
      return RefreshIndicator(
        onRefresh: () async => reload(),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${records.length} $label',
                    style: const TextStyle(color: Colors.blueGrey),
                  ),
                ),
                if (session.admin)
                  FilledButton.icon(
                    onPressed: () => edit(context, reload),
                    icon: const Icon(Icons.add),
                    label: const Text('Thêm mới'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (records.isEmpty)
              EmptyPanel(
                'Chưa có $label. ${session.admin ? 'Nhấn Thêm mới để bắt đầu.' : ''}',
              ),
            ...records.map(
              (r) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .primaryContainer,
                        child: Icon(
                          kind == 'employees'
                              ? Icons.person_outline
                              : kind == 'departments'
                              ? Icons.business_outlined
                              : Icons.schedule,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${r['fullName'] ?? r['name']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 6),
                            if (kind == 'employees') ...[
                              Text(
                                '${r['email']}\n@${r['username']}',
                                style: const TextStyle(color: Colors.blueGrey),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  StatusPill(roleLabel(r['role'])),
                                  StatusPill(
                                    r['isActive'] == true
                                        ? 'Hoạt động'
                                        : 'Đã khóa',
                                    color: r['isActive'] == true
                                        ? Colors.teal
                                        : Colors.red,
                                  ),
                                  if (r['emailVerified'] != true)
                                    const StatusPill(
                                      'Chưa xác thực',
                                      color: Colors.orange,
                                    ),
                                ],
                              ),
                            ] else if (kind == 'shifts')
                              Text(
                                '${r['startTime']} – ${r['endTime']} • Cho phép trễ ${r['graceMinutes']} phút',
                                style: const TextStyle(color: Colors.blueGrey),
                              )
                            else
                              Text(
                                '${r['description'] ?? ''}',
                                style: const TextStyle(color: Colors.blueGrey),
                              ),
                          ],
                        ),
                      ),
                      if (session.admin)
                        PopupMenuButton<String>(
                          tooltip: 'Thao tác',
                          onSelected: (action) async {
                            if (action == 'edit') {
                              await edit(context, reload, r);
                              return;
                            }
                            if (!await confirm(
                              context,
                              kind == 'employees'
                                  ? 'Khóa tài khoản?'
                                  : 'Xóa $label?',
                              kind == 'employees'
                                  ? 'Tài khoản sẽ bị vô hiệu hóa, lịch sử chấm công được giữ lại.'
                                  : 'Dữ liệu đang được sử dụng sẽ không thể xóa.',
                            )) {
                              return;
                            }
                            try {
                              await session.request(
                                'DELETE',
                                '/$kind/${r['id']}',
                              );
                              reload();
                            } catch (e) {
                              if (context.mounted) showMessage(context, e);
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Text('Chỉnh sửa'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text(
                                kind == 'employees' ? 'Khóa tài khoản' : 'Xóa',
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class RecordEditor extends StatefulWidget {
  final Session session;
  final String kind;
  final Json? existing;
  const RecordEditor({
    super.key,
    required this.session,
    required this.kind,
    this.existing,
  });
  @override
  State<RecordEditor> createState() => _RecordEditorState();
}

class _RecordEditorState extends State<RecordEditor> {
  final form = GlobalKey<FormState>();
  final Map<String, TextEditingController> controllers = {};
  String role = 'Employee';
  String departmentId = '';
  String shiftId = '';
  bool active = true;
  bool busy = false;
  String? error;
  late Future<List<dynamic>> choices;
  bool get employee => widget.kind == 'employees';
  bool get shift => widget.kind == 'shifts';
  @override
  void initState() {
    super.initState();
    final r = widget.existing;
    final keys = employee
        ? ['username', 'email', 'fullName', 'password']
        : shift
        ? ['name', 'startTime', 'endTime', 'graceMinutes']
        : ['name', 'description'];
    for (final key in keys) {
      controllers[key] = TextEditingController(
        text: r?[key]?.toString() ?? (key == 'graceMinutes' ? '10' : ''),
      );
    }
    role = r?['role']?.toString() ?? 'Employee';
    departmentId = r?['departmentId']?.toString() ?? '';
    shiftId = r?['shiftId']?.toString() ?? '';
    active = r?['isActive'] as bool? ?? true;
    choices = employee
        ? Future.wait([
            widget.session.request('GET', '/departments'),
            widget.session.request('GET', '/shifts'),
          ])
        : Future.value([]);
  }

  @override
  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (form.currentState == null || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      Json body;
      if (employee) {
        body = {
          'fullName': controllers['fullName']!.text.trim(),
          'role': role,
          'departmentId': departmentId.isEmpty ? null : departmentId,
          'shiftId': shiftId.isEmpty ? null : shiftId,
          if (widget.existing != null) 'isActive': active,
          if (widget.existing == null) ...{
            'username': controllers['username']!.text.trim(),
            'email': controllers['email']!.text.trim(),
            'password': controllers['password']!.text,
          },
        };
      } else if (shift) {
        body = {
          'name': controllers['name']!.text.trim(),
          'startTime': controllers['startTime']!.text.trim(),
          'endTime': controllers['endTime']!.text.trim(),
          'graceMinutes': int.parse(controllers['graceMinutes']!.text),
        };
      } else {
        body = {
          'name': controllers['name']!.text.trim(),
          'description': controllers['description']!.text.trim(),
        };
      }
      await widget.session.request(
        widget.existing == null ? 'POST' : 'PUT',
        '/${widget.kind}${widget.existing == null ? '' : '/${widget.existing!['id']}'}',
        body,
      );
      if (mounted) Navigator.pop(context);
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

  Widget field(
    String key,
    String label, {
    bool optional = false,
    bool secret = false,
    bool number = false,
    String? helper,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controllers[key],
      enabled: !busy,
      obscureText: secret,
      keyboardType: number
          ? TextInputType.number
          : key == 'email'
          ? TextInputType.emailAddress
          : TextInputType.text,
      maxLength: key == 'description'
          ? 500
          : key == 'fullName' || key == 'name'
          ? 120
          : null,
      decoration: InputDecoration(labelText: label, helperText: helper),
      validator: (value) {
        final v = value?.trim() ?? '';
        if (!optional && v.isEmpty) return 'Vui lòng nhập $label.';
        if (number && (int.tryParse(v) == null || int.parse(v) < 0)) {
          return 'Nhập số nguyên không âm.';
        }
        if (key == 'email' &&
            !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v)) {
          return 'Email không hợp lệ.';
        }
        if (key == 'username' &&
            !RegExp(r'^[a-zA-Z0-9_.]{3,40}$').hasMatch(v)) {
          return '3–40 chữ cái, số, dấu _ hoặc .';
        }
        if (key == 'password' &&
            (v.length < 10 ||
                !RegExp('[A-Z]').hasMatch(v) ||
                !RegExp('[a-z]').hasMatch(v) ||
                !RegExp('[0-9]').hasMatch(v))) {
          return 'Từ 10 ký tự, có chữ hoa, thường và số.';
        }
        if ((key == 'startTime' || key == 'endTime') &&
            !RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(v)) {
          return 'Nhập giờ dạng HH:mm, ví dụ 08:00.';
        }
        return null;
      },
    ),
  );
  Widget selection(
    String label,
    String value,
    List<dynamic> records,
    ValueChanged<String> change,
  ) {
    final validValue = records.any((r) => r['id'] == value) ? value : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<String>(
        initialValue: validValue,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          const DropdownMenuItem(value: '', child: Text('Chưa phân công')),
          ...records.map(
            (r) => DropdownMenuItem(
              value: r['id'].toString(),
              child: Text('${r['name']}'),
            ),
          ),
        ],
        onChanged: busy
            ? null
            : (v) => setState(() {
                change(v!);
              }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      '${widget.existing == null ? 'Thêm' : 'Sửa'} ${employee
          ? 'nhân viên'
          : shift
          ? 'ca làm'
          : 'phòng ban'}',
    ),
    content: SizedBox(
      width: 500,
      child: FutureBuilder<List<dynamic>>(
        future: choices,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorPanel(
              error: snapshot.error!,
              retry: () => setState(() {
                choices = Future.wait([
                  widget.session.request('GET', '/departments'),
                  widget.session.request('GET', '/shifts'),
                ]);
              }),
            );
          }
          if (!snapshot.hasData) {
            return const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (employee) ...[
                    if (widget.existing == null) ...[
                      field('username', 'Tên đăng nhập'),
                      field('email', 'Email'),
                      field(
                        'password',
                        'Mật khẩu',
                        secret: true,
                        helper: 'Từ 10 ký tự, có chữ hoa, chữ thường và số',
                      ),
                    ],
                    field('fullName', 'Họ và tên'),
                    DropdownButtonFormField<String>(
                      initialValue: role,
                      decoration: const InputDecoration(labelText: 'Vai trò'),
                      items: ['Employee', 'Manager', 'Admin']
                          .map(
                            (v) => DropdownMenuItem(
                              value: v,
                              child: Text(roleLabel(v)),
                            ),
                          )
                          .toList(),
                      onChanged: busy
                          ? null
                          : (v) => setState(() {
                              role = v!;
                            }),
                    ),
                    const SizedBox(height: 16),
                    selection(
                      'Phòng ban',
                      departmentId,
                      snapshot.data![0] as List,
                      (v) {
                        departmentId = v;
                      },
                    ),
                    selection('Ca làm', shiftId, snapshot.data![1] as List, (
                      v,
                    ) {
                      shiftId = v;
                    }),
                    if (widget.existing != null)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Tài khoản hoạt động'),
                        value: active,
                        onChanged: busy
                            ? null
                            : (v) => setState(() {
                                active = v;
                              }),
                      ),
                    if (widget.existing == null)
                      const Text(
                        'Nhân viên mới cần xác thực email trước khi đăng nhập.',
                        style: TextStyle(color: Colors.blueGrey, fontSize: 12),
                      ),
                  ] else ...[
                    field('name', shift ? 'Tên ca' : 'Tên phòng ban'),
                    if (shift) ...[
                      field(
                        'startTime',
                        'Giờ bắt đầu',
                        helper: 'HH:mm, ví dụ 08:00',
                      ),
                      field(
                        'endTime',
                        'Giờ kết thúc',
                        helper: 'HH:mm, cùng ngày',
                      ),
                      field('graceMinutes', 'Phút cho phép trễ', number: true),
                    ] else
                      field('description', 'Mô tả', optional: true),
                  ],
                  if (error != null)
                    Text(error!, style: const TextStyle(color: Colors.red)),
                ],
              ),
            ),
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Hủy'),
      ),
      FilledButton(
        onPressed: busy ? null : save,
        child: Text(busy ? 'Đang lưu…' : 'Lưu thay đổi'),
      ),
    ],
  );
}

class CompanySettings extends StatelessWidget {
  final Session session;
  const CompanySettings({super.key, required this.session});
  @override
  Widget build(BuildContext context) => DataPage(
    load: () => session.request('GET', '/company-settings'),
    builder: (context, data, reload) =>
        CompanyForm(session: session, initial: data as Json),
  );
}

class CompanyForm extends StatefulWidget {
  final Session session;
  final Json initial;
  const CompanyForm({super.key, required this.session, required this.initial});
  @override
  State<CompanyForm> createState() => _CompanyFormState();
}

class _CompanyFormState extends State<CompanyForm> {
  final form = GlobalKey<FormState>();
  final Map<String, TextEditingController> controllers = {};
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    for (final key in [
      'officeName',
      'latitude',
      'longitude',
      'radiusMeters',
      'maxAccuracyMeters',
      'qrLifetimeSeconds',
    ]) {
      controllers[key] = TextEditingController(text: '${widget.initial[key]}');
    }
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> usePosition() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const ApiException('Hãy bật GPS.');
      }
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      if (p == LocationPermission.denied ||
          p == LocationPermission.deniedForever) {
        throw const ApiException('Cần cấp quyền vị trí.');
      }
      final value = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 25),
        ),
      );
      if (mounted) {
        setState(() {
          controllers['latitude']!.text = '${value.latitude}';
          controllers['longitude']!.text = '${value.longitude}';
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

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.session.request('PUT', '/company-settings', {
        'officeName': controllers['officeName']!.text.trim(),
        for (final key in [
          'latitude',
          'longitude',
          'radiusMeters',
          'maxAccuracyMeters',
        ])
          key: double.parse(controllers[key]!.text),
        'qrLifetimeSeconds': int.parse(controllers['qrLifetimeSeconds']!.text),
      });
      if (mounted) showMessage(context, 'Đã lưu thiết lập văn phòng.');
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
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Form(
      key: form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Đặt vị trí văn phòng thật trước khi chấm công. Thay đổi áp dụng cho các lượt chấm công tiếp theo.',
            style: TextStyle(color: Colors.blueGrey),
          ),
          const SizedBox(height: 20),
          for (final item in <String, String>{
            'officeName': 'Tên văn phòng',
            'latitude': 'Vĩ độ (−90 đến 90)',
            'longitude': 'Kinh độ (−180 đến 180)',
            'radiusMeters': 'Bán kính chấm công (20–5000 m)',
            'maxAccuracyMeters': 'Sai số GPS tối đa (5–500 m)',
            'qrLifetimeSeconds': 'Thời hạn QR (15–300 giây)',
          }.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: TextFormField(
                controller: controllers[item.key],
                enabled: !busy,
                keyboardType: item.key == 'officeName'
                    ? TextInputType.text
                    : const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                decoration: InputDecoration(labelText: item.value),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Vui lòng nhập giá trị.';
                  }
                  if (item.key == 'officeName') {
                    return v.trim().length > 120 ? 'Tối đa 120 ký tự.' : null;
                  }
                  final value = double.tryParse(v);
                  if (value == null || !value.isFinite) {
                    return 'Nhập số hợp lệ.';
                  }
                  final bounds = <String, List<double>>{
                    'latitude': [-90, 90],
                    'longitude': [-180, 180],
                    'radiusMeters': [20, 5000],
                    'maxAccuracyMeters': [5, 500],
                    'qrLifetimeSeconds': [15, 300],
                  }[item.key]!;
                  if (value < bounds[0] || value > bounds[1]) {
                    return 'Giá trị ngoài phạm vi cho phép.';
                  }
                  if (item.key == 'qrLifetimeSeconds' &&
                      int.tryParse(v) == null) {
                    return 'Nhập số giây nguyên.';
                  }
                  return null;
                },
              ),
            ),
          OutlinedButton.icon(
            onPressed: busy ? null : usePosition,
            icon: const Icon(Icons.my_location),
            label: const Text('Lấy tọa độ từ thiết bị hiện tại'),
          ),
          const SizedBox(height: 16),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(error!, style: const TextStyle(color: Colors.red)),
            ),
          FilledButton(
            onPressed: busy ? null : save,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(busy ? 'Đang xử lý…' : 'Lưu thiết lập'),
            ),
          ),
        ],
      ),
    ),
  );
}
