import 'package:flutter/material.dart';

import 'core.dart';
import 'attendance.dart';
import 'leaves.dart';
import 'admin.dart';
import 'incidents.dart';

class HomeScreen extends StatefulWidget {
  final Session session;
  const HomeScreen({super.key, required this.session});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int index = 0;
  int revision = 0;
  @override
  void initState() {
    super.initState();
    index = widget.session.admin ? 4 : 0;
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final labels = [
      'Tổng quan',
      'Chấm công',
      'Lịch sử',
      'Đơn từ',
      if (session.manager) session.admin ? 'Quản trị' : 'Đội ngũ',
    ];
    const icons = [
      Icons.space_dashboard_outlined,
      Icons.qr_code_scanner_rounded,
      Icons.history_rounded,
      Icons.description_outlined,
      Icons.admin_panel_settings_outlined,
    ];
    const selectedIcons = [
      Icons.space_dashboard_rounded,
      Icons.qr_code_scanner_rounded,
      Icons.history_rounded,
      Icons.description_rounded,
      Icons.admin_panel_settings_rounded,
    ];
    final pages = [
      Dashboard(
        session: session,
        onAttendance: () => setState(() {
          index = 1;
        }),
      ),
      AttendanceScreen(session: session),
      AttendanceHistory(session: session),
      LeavesScreen(session: session),
      if (session.manager) AdminScreen(session: session),
    ];
    final wide = MediaQuery.sizeOf(context).width >= 800;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Chấm công Hữu Duyên',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Sự cố chấm công',
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => IncidentsScreen(session: session),
              ),
            ),
            icon: const Icon(Icons.report_problem_outlined),
          ),
          IconButton(
            tooltip: 'Làm mới dữ liệu',
            onPressed: () => setState(() {
              revision++;
            }),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Tài khoản',
            icon: CircleAvatar(
              radius: 16,
              backgroundColor: brandPrimary,
              child: Text(
                initials(session.user!['fullName']),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (context) => SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 34,
                        backgroundColor: brandPrimary,
                        child: Text(
                          initials(session.user!['fullName']),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        session.user!['fullName'].toString(),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: brandInk,
                        ),
                      ),
                      const SizedBox(height: 6),
                      StatusPill(roleLabel(session.user!['role'])),
                      const SizedBox(height: 16),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const IconBadge(Icons.email_outlined, size: 40),
                        title: Text(session.user!['email'].toString()),
                        subtitle: const Text('Email'),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const IconBadge(Icons.dns_outlined, size: 40),
                        title: Text(session.baseUrl),
                        subtitle: const Text('Máy chủ API'),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            foregroundColor: Colors.red.shade700,
                            backgroundColor: Colors.red.shade50,
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                            session.logout();
                          },
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text('Đăng xuất'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Row(
          children: [
            if (wide)
              NavigationRail(
                extended: true,
                selectedIndex: index,
                onDestinationSelected: (value) => setState(() {
                  index = value;
                }),
                destinations: List.generate(
                  labels.length,
                  (i) => NavigationRailDestination(
                    icon: Icon(icons[i]),
                    label: Text(labels[i]),
                  ),
                ),
              ),
            Expanded(
              child: KeyedSubtree(
                key: ValueKey('$index-$revision'),
                child: pages[index],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (value) => setState(() {
                index = value;
              }),
              destinations: List.generate(
                labels.length,
                (i) => NavigationDestination(
                  icon: Icon(icons[i]),
                  selectedIcon: Icon(selectedIcons[i], color: brandDeep),
                  label: labels[i],
                ),
              ),
            ),
    );
  }
}

class Dashboard extends StatelessWidget {
  final Session session;
  final VoidCallback onAttendance;
  const Dashboard({
    super.key,
    required this.session,
    required this.onAttendance,
  });
  @override
  Widget build(BuildContext context) => DataPage(
    load: () async {
      final results = await Future.wait([
        session.request('GET', '/attendance/summary'),
        session.request('GET', '/attendance'),
      ]);
      return {'summary': results[0], 'records': results[1]};
    },
    builder: (context, data, reload) {
      final summary = data['summary'] as Json;
      final records = (data['records'] as List).cast<Json>();
      final missing = records
          .where(
            (r) =>
                r['employeeId'] == session.user!['id'] &&
                r['checkOutAtUtc'] == null &&
                r['workDate'].toString().compareTo(dateOnly(businessNow())) < 0,
          )
          .toList();
      final status = summary['todayStatus'];
      return RefreshIndicator(
        onRefresh: () async => reload(),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Text(
                      initials(session.user!['fullName']),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: brandDeep,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Xin chào, ${session.user!['fullName']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: brandInk,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${roleLabel(session.user!['role'])} • ${displayDate(dateOnly(businessNow()))}',
                          style: const TextStyle(color: brandMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: brandGradient,
                borderRadius: BorderRadius.circular(26),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x402455D6),
                    blurRadius: 24,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'CA LÀM HÔM NAY',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.6,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          status == 'Working'
                              ? '● Đang làm'
                              : status == 'Completed'
                              ? '✓ Hoàn tất'
                              : '○ Chưa vào ca',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    status == 'Working'
                        ? 'Bạn đang trong ca làm'
                        : status == 'Completed'
                        ? 'Đã hoàn thành ca làm'
                        : 'Sẵn sàng cho ngày mới',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _timeTile(
                        'Giờ vào',
                        localTime(summary['checkedInAtUtc']),
                        Icons.login_rounded,
                      ),
                      const SizedBox(width: 10),
                      _timeTile(
                        'Giờ ra',
                        localTime(summary['checkedOutAtUtc']),
                        Icons.logout_rounded,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: brandDeep,
                      ),
                      onPressed: status == 'Completed' ? null : onAttendance,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: Text(
                        status == 'Working'
                            ? 'Chấm công ra'
                            : status == 'Completed'
                            ? 'Hẹn gặp lại ngày mai'
                            : 'Mở chấm công',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const SectionTitle('Tháng này của bạn'),
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _stat(
                    context,
                    constraints.maxWidth,
                    '${summary['totalDaysThisMonth'] ?? 0}',
                    'Ngày có mặt',
                    Icons.calendar_month_outlined,
                    Colors.blue,
                  ),
                  _stat(
                    context,
                    constraints.maxWidth,
                    '${summary['totalHoursThisMonth'] ?? 0}',
                    'Giờ làm việc',
                    Icons.schedule,
                    Colors.teal,
                  ),
                  _stat(
                    context,
                    constraints.maxWidth,
                    '${summary['lateDaysThisMonth'] ?? 0}',
                    'Ngày đến muộn',
                    Icons.timer_outlined,
                    Colors.orange,
                  ),
                  _stat(
                    context,
                    constraints.maxWidth,
                    '${summary['missingCheckoutCount'] ?? 0}',
                    'Thiếu giờ ra',
                    Icons.warning_amber_rounded,
                    Colors.deepPurple,
                  ),
                ],
              ),
            ),
            if (missing.isNotEmpty) ...[
              const SizedBox(height: 24),
              Card(
                color: const Color(0xFFFFF4DE),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.auto_awesome_outlined,
                            color: Colors.deepOrange,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Trợ lý bổ sung công',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Bạn còn ${missing.length} ngày chưa có giờ ra. Tạo đề xuất để quản lý xem xét, tránh bỏ sót khi tổng hợp công.',
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () async {
                          await editLeave(
                            context,
                            session,
                            suggestion: missing.first,
                          );
                          reload();
                        },
                        child: Text(
                          'Đề xuất ngày ${displayDate(missing.first['workDate'])}',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Chấm công rõ ràng, mỗi ngày',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '1. Quét mã QR do quản lý cung cấp.\n2. Lấy vị trí tại văn phòng và đo chuyển động.\n3. Xác nhận vào ca hoặc ra ca.\n\nDữ liệu cảm biến hỗ trợ minh bạch; không chứng minh chống giả mạo vị trí.',
                    ),
                    if (session.user!['shiftId'] == null)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(
                          'Tài khoản chưa có ca làm. Liên hệ quản trị viên để phân ca trước khi chấm công.',
                          style: TextStyle(color: Colors.deepOrange),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
  Widget _stat(
    BuildContext context,
    double available,
    String value,
    String label,
    IconData icon,
    Color color,
  ) => SizedBox(
    width: available >= 800 ? (available - 36) / 4 : (available - 12) / 2,
    child: Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconBadge(icon, color: color, size: 40),
            const SizedBox(height: 14),
            Text(
              value,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: brandInk,
              ),
            ),
            Text(label, style: const TextStyle(color: brandMuted)),
          ],
        ),
      ),
    ),
  );

  Widget _timeTile(String label, String value, IconData icon) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class AttendanceHistory extends StatefulWidget {
  final Session session;
  const AttendanceHistory({super.key, required this.session});
  @override
  State<AttendanceHistory> createState() => _AttendanceHistoryState();
}

class _AttendanceHistoryState extends State<AttendanceHistory> {
  DateTimeRange? range;
  int revision = 0;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        child: SectionTitle(
          widget.session.manager ? 'Báo cáo chấm công' : 'Lịch sử chấm công',
          subtitle: 'Múi giờ Việt Nam • UTC+7',
          trailing: IconButton(
            tooltip: 'Lọc ngày',
            icon: const Icon(Icons.date_range_outlined),
            onPressed: () async {
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
                initialDateRange: range,
                helpText: 'Chọn khoảng ngày',
              );
              if (picked != null && mounted) {
                setState(() {
                  range = picked;
                  revision++;
                });
              }
            },
          ),
        ),
      ),
      if (range != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Align(
            alignment: Alignment.centerLeft,
            child: InputChip(
              label: Text(
                '${displayDate(dateOnly(range!.start))} – ${displayDate(dateOnly(range!.end))}',
              ),
              onDeleted: () => setState(() {
                range = null;
                revision++;
              }),
            ),
          ),
        ),
      Expanded(
        child: DataPage(
          key: ValueKey(revision),
          load: () => widget.session.request(
            'GET',
            '/attendance${range == null ? '' : '?from=${dateOnly(range!.start)}&to=${dateOnly(range!.end)}'}',
          ),
          builder: (context, data, reload) {
            final records = (data as List).cast<Json>();
            if (records.isEmpty) {
              return const EmptyPanel(
                'Chưa có lượt chấm công trong khoảng ngày này.',
              );
            }
            final minutes = records.fold<num>(
              0,
              (sum, r) => sum + (r['workedMinutes'] as num? ?? 0),
            );
            return RefreshIndicator(
              onRefresh: () async => reload(),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    '${records.length} bản ghi • ${(minutes / 60).toStringAsFixed(1)} giờ • ${records.where((r) => r['isLate'] == true).length} lượt muộn',
                    style: const TextStyle(color: Colors.blueGrey),
                  ),
                  const SizedBox(height: 12),
                  ...records.map(
                    (r) => Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${r['employeeName']}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                StatusPill(
                                  r['isLate'] == true ? 'Đến muộn' : 'Đúng giờ',
                                  color: r['isLate'] == true
                                      ? Colors.deepOrange
                                      : Colors.teal,
                                ),
                              ],
                            ),
                            Text(
                              '${displayDate(r['workDate'])} • ${r['departmentName'] ?? 'Chưa phân phòng'}',
                              style: const TextStyle(color: Colors.blueGrey),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Vào ${localTime(r['checkInAtUtc'])}     Ra ${localTime(r['checkOutAtUtc'])}     ${r['workedMinutes'] ?? 0} phút',
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'GPS ${r['latitude']}, ${r['longitude']} • Sai số ${r['accuracyMeters']} m\nChuyển động ${r['motionScore']} m/s²',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.blueGrey,
                              ),
                            ),
                            if (r['checkOutAtUtc'] == null &&
                                r['employeeId'] == widget.session.user!['id'] &&
                                r['workDate'].toString().compareTo(
                                      dateOnly(businessNow()),
                                    ) <
                                    0)
                              TextButton.icon(
                                onPressed: () async {
                                  await editLeave(
                                    context,
                                    widget.session,
                                    suggestion: r,
                                  );
                                  reload();
                                },
                                icon: const Icon(Icons.auto_awesome_outlined),
                                label: const Text('Tạo đề xuất bổ sung công'),
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
        ),
      ),
    ],
  );
}
