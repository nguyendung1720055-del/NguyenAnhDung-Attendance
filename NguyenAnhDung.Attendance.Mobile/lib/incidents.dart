import 'package:flutter/material.dart';

import 'core.dart';

String incidentReviewLabel(dynamic value) => switch (value) {
  'Approved' => 'Đã chấp nhận',
  'Rejected' => 'Đã từ chối',
  _ => 'Chờ xét duyệt',
};

Color incidentReviewColor(dynamic value) => switch (value) {
  'Approved' => Colors.teal,
  'Rejected' => Colors.red,
  _ => Colors.orange,
};

class IncidentsScreen extends StatelessWidget {
  final Session session;
  const IncidentsScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Sự cố chấm công',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
    body: SafeArea(child: IncidentsPanel(session: session)),
  );
}

class IncidentsPanel extends StatefulWidget {
  final Session session;
  const IncidentsPanel({super.key, required this.session});

  @override
  State<IncidentsPanel> createState() => _IncidentsPanelState();
}

class _IncidentsPanelState extends State<IncidentsPanel> {
  late Future<List<Json>> future;

  @override
  void initState() {
    super.initState();
    future = load();
  }

  Future<List<Json>> load() async =>
      (await widget.session.request('GET', '/attendance-incidents') as List)
          .cast<Json>();

  Future<void> refresh() async {
    final next = load();
    setState(() {
      future = next;
    });
    try {
      await next;
    } catch (_) {
      // FutureBuilder displays the error and a retry action.
    }
  }

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 960),
      child: FutureBuilder<List<Json>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return SingleChildScrollView(
              child: ErrorPanel(error: snapshot.error!, retry: refresh),
            );
          }
          final records = snapshot.data!;
          return RefreshIndicator(
            onRefresh: refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                SectionTitle(
                  'Sự cố chấm công',
                  subtitle: widget.session.manager
                      ? 'Xem các lỗi được ghi nhận và xét giải trình cho đội ngũ.'
                      : 'Theo dõi sự cố và kết quả xét giải trình của bạn.',
                  trailing: IconButton(
                    tooltip: 'Làm mới sự cố',
                    onPressed: refresh,
                    icon: const Icon(Icons.refresh),
                  ),
                ),
                const Text(
                  'Sự cố được gom từ các lần chấm công bị lỗi. Chấp nhận giải trình không tự sửa giờ vào, giờ ra hoặc trạng thái đi muộn.',
                ),
                const SizedBox(height: 16),
                if (records.isEmpty)
                  const EmptyPanel('Chưa có sự cố chấm công được ghi nhận.'),
                for (final record in records)
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () async {
                        await Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => IncidentDetailScreen(
                              session: widget.session,
                              incidentId: '${record['id']}',
                            ),
                          ),
                        );
                        if (mounted) await refresh();
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${record['errorLabel']}',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text('${record['officeName']}'),
                            const SizedBox(height: 8),
                            Text(
                              'Ghi nhận: ${localTime(record['firstOccurredAtUtc'], date: true)}\nGần nhất: ${localTime(record['lastOccurredAtUtc'], date: true)}',
                              style: const TextStyle(color: Colors.blueGrey),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                StatusPill(
                                  record['status'] == 'Resolved'
                                      ? 'Đã xử lý'
                                      : 'Chờ xử lý',
                                  color: record['status'] == 'Resolved'
                                      ? Colors.teal
                                      : Colors.orange,
                                ),
                                StatusPill(
                                  '${record['affectedEmployeeCount']} người ảnh hưởng',
                                ),
                                StatusPill(
                                  '${record['pendingCount']} chờ xét duyệt',
                                ),
                                if (record['myReviewStatus'] != null)
                                  StatusPill(
                                    'Của bạn: ${incidentReviewLabel(record['myReviewStatus'])}',
                                    color: incidentReviewColor(
                                      record['myReviewStatus'],
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            const Text('Xem chi tiết →'),
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
  );
}

class IncidentDetailScreen extends StatefulWidget {
  final Session session;
  final String incidentId;
  const IncidentDetailScreen({
    super.key,
    required this.session,
    required this.incidentId,
  });

  @override
  State<IncidentDetailScreen> createState() => _IncidentDetailScreenState();
}

class _IncidentDetailScreenState extends State<IncidentDetailScreen> {
  late Future<Json> future;
  final selected = <String>{};
  final note = TextEditingController();
  final form = GlobalKey<FormState>();
  bool busy = false;
  String? error;
  String? success;

  @override
  void initState() {
    super.initState();
    future = load();
  }

  Future<Json> load() async => await widget.session.request(
    'GET',
    '/attendance-incidents/${widget.incidentId}',
  ) as Json;

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    if (busy) return;
    final next = load();
    setState(() {
      future = next;
      selected.clear();
      error = null;
      success = null;
    });
    try {
      await next;
    } catch (_) {
      // The detail view offers retry when the server request fails.
    }
  }

  Future<void> review(String status) async {
    if (busy || selected.isEmpty || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
      success = null;
    });
    try {
      final result = await widget.session.request(
        'POST',
        '/attendance-incidents/${widget.incidentId}/review',
        {
          'participantIds': selected.toList(),
          'status': status,
          'reviewNote': note.text.trim(),
        },
      );
      if (!mounted) return;
      setState(() {
        future = Future<Json>.value(result as Json);
        selected.clear();
        note.clear();
        success = 'Đã lưu kết quả xét giải trình.';
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget participant(Json record) {
    final own = record['employeeId'] == widget.session.user?['id'];
    final selectable =
        widget.session.manager && record['status'] == 'Pending' && !own;
    final participantId = '${record['id']}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (selectable)
              CheckboxListTile(
                key: ValueKey('participant-$participantId'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text('${record['employeeName']}'),
                subtitle: Text('@${record['username']}'),
                value: selected.contains(participantId),
                onChanged: busy
                    ? null
                    : (value) => setState(() {
                        if (value == true) {
                          selected.add(participantId);
                        } else {
                          selected.remove(participantId);
                        }
                      }),
              )
            else ...[
              Text(
                '${record['employeeName']}${own ? ' (Bạn)' : ''}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('@${record['username']}'),
            ],
            const SizedBox(height: 8),
            StatusPill(
              incidentReviewLabel(record['status']),
              color: incidentReviewColor(record['status']),
            ),
            const SizedBox(height: 8),
            Text(
              '${record['attemptCount']} lần thử\nLần đầu: ${localTime(record['firstAttemptAtUtc'], date: true)}\nGần nhất: ${localTime(record['lastAttemptAtUtc'], date: true)}',
              style: const TextStyle(color: Colors.blueGrey),
            ),
            if (own && widget.session.manager && record['status'] == 'Pending')
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Cần người quản lý khác xét giải trình của bạn.'),
              ),
            if (record['reviewNote'] != null) ...[
              const SizedBox(height: 12),
              Text('Ghi chú: ${record['reviewNote']}'),
              Text(
                'Người xét: ${record['reviewerName'] ?? '—'}\nThời điểm: ${localTime(record['reviewedAtUtc'], date: true)}',
                style: const TextStyle(color: Colors.blueGrey),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Chi tiết sự cố',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        IconButton(
          tooltip: 'Làm mới sự cố',
          onPressed: busy ? null : refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: FutureBuilder<Json>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return SingleChildScrollView(
                  child: ErrorPanel(error: snapshot.error!, retry: refresh),
                );
              }
              final incident = snapshot.data!;
              final participants = (incident['participants'] as List)
                  .cast<Json>()
                  .where(
                    (p) =>
                        widget.session.manager ||
                        p['employeeId'] == widget.session.user?['id'],
                  )
                  .toList();
              final canReview =
                  widget.session.manager &&
                  participants.any(
                    (p) =>
                        p['status'] == 'Pending' &&
                        p['employeeId'] != widget.session.user?['id'],
                  );
              return RefreshIndicator(
                onRefresh: refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(20),
                  children: [
                    SectionTitle(
                      '${incident['errorLabel']}',
                      subtitle: '${incident['officeName']}',
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        StatusPill(
                          incident['status'] == 'Resolved'
                              ? 'Đã xử lý'
                              : 'Chờ xử lý',
                        ),
                        StatusPill(
                          '${incident['affectedEmployeeCount']} người ảnh hưởng',
                        ),
                        StatusPill('${incident['pendingCount']} chờ xét duyệt'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Từ ${localTime(incident['firstOccurredAtUtc'], date: true)} đến ${localTime(incident['lastOccurredAtUtc'], date: true)} (UTC+7)',
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Xét duyệt chỉ ghi nhận giải trình sự cố. Giờ vào, giờ ra và trạng thái đi muộn không tự thay đổi. Bạn có thể gửi đơn bổ sung thông tin công để quản lý xem xét.',
                    ),
                    const SizedBox(height: 20),
                    Text(
                      widget.session.manager
                          ? 'Nhân viên bị ảnh hưởng'
                          : 'Thông tin của bạn',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (participants.isEmpty)
                      const EmptyPanel('Chưa có lần thử được ghi nhận.'),
                    ...participants.map(participant),
                    if (canReview) ...[
                      const SizedBox(height: 20),
                      Text(
                        'Đã chọn ${selected.length} người',
                        key: const ValueKey('incident-selection-count'),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Chọn từng người đang chờ xét duyệt, rồi nhập ghi chú áp dụng cho những người đã chọn.',
                      ),
                      const SizedBox(height: 12),
                      Form(
                        key: form,
                        child: TextFormField(
                          key: const ValueKey('incident-review-note'),
                          controller: note,
                          enabled: !busy,
                          minLines: 2,
                          maxLines: 5,
                          maxLength: 1000,
                          decoration: const InputDecoration(
                            labelText: 'Ghi chú xét duyệt',
                            helperText: 'Từ 5 đến 1000 ký tự',
                          ),
                          validator: (value) {
                            final length = value?.trim().length ?? 0;
                            return length < 5 || length > 1000
                                ? 'Ghi chú cần từ 5 đến 1000 ký tự.'
                                : null;
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          FilledButton.icon(
                            key: const ValueKey('incident-approve'),
                            onPressed: busy || selected.isEmpty
                                ? null
                                : () => review('Approved'),
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('Chấp nhận giải trình'),
                          ),
                          OutlinedButton.icon(
                            key: const ValueKey('incident-reject'),
                            onPressed: busy || selected.isEmpty
                                ? null
                                : () => review('Rejected'),
                            icon: const Icon(Icons.cancel_outlined),
                            label: const Text('Từ chối giải trình'),
                          ),
                        ],
                      ),
                    ],
                    if (busy)
                      const Padding(
                        padding: EdgeInsets.only(top: 16),
                        child: LinearProgressIndicator(),
                      ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    if (success != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          success!,
                          style: const TextStyle(color: Colors.teal),
                        ),
                      ),
                    const SizedBox(height: 24),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}
