import 'package:flutter/material.dart';

import 'core.dart';

Future<void> editLeave(
  BuildContext context,
  Session session, {
  Json? existing,
  Json? suggestion,
}) async {
  await showDialog<bool>(
    context: context,
    builder: (_) => LeaveEditor(
      session: session,
      existing: existing,
      suggestion: suggestion,
    ),
  );
}

class LeavesScreen extends StatelessWidget {
  final Session session;
  const LeavesScreen({super.key, required this.session});
  @override
  Widget build(BuildContext context) => DataPage(
    load: () => session.request('GET', '/leave-requests'),
    builder: (context, data, reload) {
      final records = (data as List).cast<Json>();
      return RefreshIndicator(
        onRefresh: () async => reload(),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            SectionTitle(
              'Đơn từ',
              subtitle: session.manager
                  ? 'Theo dõi và phê duyệt yêu cầu đội ngũ'
                  : 'Nghỉ phép và đề xuất bổ sung công',
              trailing: FilledButton.icon(
                onPressed: () async {
                  await editLeave(context, session);
                  reload();
                },
                icon: const Icon(Icons.add),
                label: const Text('Tạo đơn'),
              ),
            ),
            if (records.isEmpty)
              const EmptyPanel(
                'Chưa có đơn. Tạo yêu cầu nghỉ phép hoặc bổ sung chấm công.',
              ),
            ...records.map((r) {
              final own = r['employeeId'] == session.user!['id'];
              final pending = r['status'] == 'Pending';
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              leaveLabel(r['type']),
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          StatusPill(
                            statusLabel(r['status']),
                            color: r['status'] == 'Approved'
                                ? Colors.teal
                                : r['status'] == 'Rejected'
                                ? Colors.red
                                : Colors.orange,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${r['employeeName']} • ${displayDate(r['startDate'])} – ${displayDate(r['endDate'])}',
                        style: const TextStyle(color: Colors.blueGrey),
                      ),
                      const SizedBox(height: 12),
                      Text('${r['reason']}'),
                      if (r['reviewNote'] != null || r['reviewerName'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            'Người duyệt: ${r['reviewerName'] ?? '—'}\nGhi chú: ${r['reviewNote'] ?? '—'}',
                            style: const TextStyle(color: Colors.blueGrey),
                          ),
                        ),
                      if (pending)
                        Wrap(
                          spacing: 8,
                          children: [
                            if (own) ...[
                              TextButton.icon(
                                onPressed: () async {
                                  await editLeave(
                                    context,
                                    session,
                                    existing: r,
                                  );
                                  reload();
                                },
                                icon: const Icon(Icons.edit_outlined),
                                label: const Text('Chỉnh sửa'),
                              ),
                              TextButton.icon(
                                onPressed: () async {
                                  if (!await confirm(
                                    context,
                                    'Xóa đơn?',
                                    'Đơn đang chờ duyệt sẽ được xóa.',
                                  )) {
                                    return;
                                  }
                                  try {
                                    await session.request(
                                      'DELETE',
                                      '/leave-requests/${r['id']}',
                                    );
                                    reload();
                                  } catch (e) {
                                    if (context.mounted) {
                                      showMessage(context, e);
                                    }
                                  }
                                },
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Xóa'),
                              ),
                            ],
                            if (!own && session.manager)
                              TextButton.icon(
                                onPressed: () async {
                                  await showDialog<void>(
                                    context: context,
                                    builder: (_) => ReviewDialog(
                                      session: session,
                                      record: r,
                                    ),
                                  );
                                  reload();
                                },
                                icon: const Icon(Icons.fact_check_outlined),
                                label: const Text('Xét duyệt'),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      );
    },
  );
}

class LeaveEditor extends StatefulWidget {
  final Session session;
  final Json? existing;
  final Json? suggestion;
  const LeaveEditor({
    super.key,
    required this.session,
    this.existing,
    this.suggestion,
  });
  @override
  State<LeaveEditor> createState() => _LeaveEditorState();
}

class _LeaveEditorState extends State<LeaveEditor> {
  final form = GlobalKey<FormState>();
  late TextEditingController reason;
  late String type;
  late DateTime start;
  late DateTime end;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    final r = widget.existing;
    final s = widget.suggestion;
    type = r?['type']?.toString() ?? (s == null ? 'Annual' : 'Correction');
    start =
        DateTime.tryParse('${r?['startDate'] ?? s?['workDate']}') ??
        businessNow();
    end = DateTime.tryParse('${r?['endDate'] ?? s?['workDate']}') ?? start;
    reason = TextEditingController(
      text:
          r?['reason']?.toString() ??
          (s == null
              ? ''
              : 'Đề nghị bổ sung giờ ra ngày ${displayDate(s['workDate'])}. Giờ vào đã ghi nhận: ${localTime(s['checkInAtUtc'])}. Giờ ra đề nghị: [nhập giờ thực tế]. Lý do: [nhập lý do].'),
    );
  }

  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  Future<void> pick(bool first) async {
    final date = await showDatePicker(
      context: context,
      initialDate: first ? start : end,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date != null && mounted) {
      setState(() {
        if (first) {
          start = date;
          if (end.isBefore(start)) end = start;
        } else {
          end = date;
        }
      });
    }
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    if (end.isBefore(start)) {
      setState(() {
        error = 'Ngày kết thúc phải sau hoặc bằng ngày bắt đầu.';
      });
      return;
    }
    if (reason.text.contains('[nhập')) {
      setState(() {
        error = 'Hãy điền giờ ra thực tế và lý do vào phần gợi ý.';
      });
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.session.request(
        widget.existing == null ? 'POST' : 'PUT',
        '/leave-requests${widget.existing == null ? '' : '/${widget.existing!['id']}'}',
        {
          'type': type,
          'startDate': dateOnly(start),
          'endDate': dateOnly(end),
          'reason': reason.text.trim(),
        },
      );
      if (mounted) Navigator.pop(context, true);
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
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.existing == null ? 'Tạo yêu cầu' : 'Chỉnh sửa yêu cầu'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: const InputDecoration(labelText: 'Loại yêu cầu'),
                items: ['Annual', 'Sick', 'Unpaid', 'Correction']
                    .map(
                      (v) => DropdownMenuItem(
                        value: v,
                        child: Text(leaveLabel(v)),
                      ),
                    )
                    .toList(),
                onChanged: busy
                    ? null
                    : (v) => setState(() {
                        type = v!;
                      }),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: busy ? null : () => pick(true),
                icon: const Icon(Icons.event),
                label: Text('Từ ${displayDate(dateOnly(start))}'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : () => pick(false),
                icon: const Icon(Icons.event),
                label: Text('Đến ${displayDate(dateOnly(end))}'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: reason,
                enabled: !busy,
                minLines: 3,
                maxLines: 7,
                maxLength: 2000,
                decoration: const InputDecoration(
                  labelText: 'Lý do / nội dung đề nghị',
                ),
                validator: (v) => (v?.trim().length ?? 0) < 5
                    ? 'Nhập ít nhất 5 ký tự.'
                    : null,
              ),
              if (type == 'Correction')
                const Text(
                  'Đề xuất cần được quản lý xem xét. Việc duyệt đơn không tự sửa giờ chấm công.',
                  style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Hủy'),
      ),
      FilledButton(
        onPressed: busy ? null : save,
        child: Text(busy ? 'Đang gửi…' : 'Gửi yêu cầu'),
      ),
    ],
  );
}

class ReviewDialog extends StatefulWidget {
  final Session session;
  final Json record;
  const ReviewDialog({super.key, required this.session, required this.record});
  @override
  State<ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<ReviewDialog> {
  final note = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  Future<void> review(String status) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.session.request(
        'PATCH',
        '/leave-requests/${widget.record['id']}/review',
        {'status': status, 'reviewNote': note.text.trim()},
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

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Xét duyệt yêu cầu'),
    content: SizedBox(
      width: 450,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.record['employeeName']} • ${leaveLabel(widget.record['type'])}',
            ),
            const SizedBox(height: 12),
            Text('${widget.record['reason']}'),
            const SizedBox(height: 16),
            TextField(
              controller: note,
              enabled: !busy,
              maxLines: 3,
              maxLength: 1000,
              decoration: const InputDecoration(labelText: 'Ghi chú phản hồi'),
            ),
            if (error != null)
              Text(error!, style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Đóng'),
      ),
      OutlinedButton(
        onPressed: busy ? null : () => review('Rejected'),
        child: const Text('Từ chối'),
      ),
      FilledButton(
        onPressed: busy ? null : () => review('Approved'),
        child: Text(busy ? 'Đang lưu…' : 'Phê duyệt'),
      ),
    ],
  );
}
