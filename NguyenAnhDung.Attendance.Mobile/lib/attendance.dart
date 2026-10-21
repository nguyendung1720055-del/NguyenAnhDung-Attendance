import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'core.dart';

class AttendanceScreen extends StatefulWidget {
  final Session session;
  const AttendanceScreen({super.key, required this.session});
  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  Position? position;
  String? qrToken;
  double? motionScore;
  UserAccelerometerEvent? latest;
  StreamSubscription<UserAccelerometerEvent>? subscription;
  String? error;
  bool locating = false;
  bool measuring = false;
  bool submitting = false;
  int samples = 0;
  int revision = 0;
  @override
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }

  Future<void> locate() async {
    setState(() {
      locating = true;
      error = null;
      position = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const ApiException('Hãy bật GPS trên điện thoại và thử lại.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        throw const ApiException(
          'Quyền vị trí bị chặn. Mở cài đặt ứng dụng để cấp quyền.',
        );
      }
      if (permission == LocationPermission.denied) {
        throw const ApiException(
          'Cần cho phép vị trí để chấm công tại văn phòng.',
        );
      }
      final result = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 25),
        ),
      );
      if (mounted) {
        setState(() {
          position = result;
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
          locating = false;
        });
      }
    }
  }

  Future<void> measure() async {
    await subscription?.cancel();
    if (!mounted) return;
    setState(() {
      measuring = true;
      error = null;
      motionScore = null;
      samples = 0;
      latest = null;
    });
    double squared = 0;
    Object? sensorError;
    try {
      subscription =
          userAccelerometerEventStream(
            samplingPeriod: const Duration(milliseconds: 100),
          ).listen(
            (event) {
              if (!mounted) return;
              squared +=
                  event.x * event.x + event.y * event.y + event.z * event.z;
              setState(() {
                samples++;
                latest = event;
              });
            },
            onError: (Object e) {
              sensorError = e;
            },
          );
    } catch (e) {
      sensorError = e;
    }
    await Future<void>.delayed(const Duration(seconds: 3));
    await subscription?.cancel();
    subscription = null;
    if (!mounted) return;
    setState(() {
      measuring = false;
      if (sensorError != null || samples == 0) {
        error = 'Không đọc được cảm biến gia tốc. Kiểm tra trên điện thoại thật có cảm biến và cho phép Chuyển động trên iOS.';
      } else {
        motionScore = math.sqrt(squared / samples);
      }
    });
  }

  Future<void> scan() async {
    final value = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
    if (value != null && mounted) {
      setState(() {
        qrToken = value;
        error = null;
      });
    }
  }

  Future<void> submit(bool checkout) async {
    if (position == null ||
        motionScore == null ||
        (!checkout && qrToken == null)) {
      setState(() {
        error = checkout
            ? 'Lấy vị trí và đo chuyển động trước khi xác nhận.'
            : 'Quét QR, lấy vị trí và đo chuyển động trước khi xác nhận.';
      });
      return;
    }
    if (DateTime.now().difference(position!.timestamp).inMinutes >= 2) {
      setState(() {
        error = 'Vị trí đã cũ. Hãy lấy lại vị trí hiện tại.';
      });
      return;
    }
    setState(() {
      submitting = true;
      error = null;
    });
    try {
      await widget.session.request(
        'POST',
        checkout ? '/attendance/check-out' : '/attendance/check-in',
        {
          'latitude': position!.latitude,
          'longitude': position!.longitude,
          'accuracyMeters': position!.accuracy,
          'motionScore': motionScore,
          if (!checkout) 'qrToken': qrToken,
        },
      );
      if (mounted) {
        showMessage(
          context,
          checkout
              ? 'Đã chấm công ra. Hẹn gặp bạn ca tiếp theo!'
              : 'Đã chấm công vào. Chúc bạn làm việc hiệu quả!',
        );
        setState(() {
          revision++;
          qrToken = null;
          position = null;
          motionScore = null;
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
          submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => DataPage(
    key: ValueKey(revision),
    load: () async {
      final result = await Future.wait([
        widget.session.request('GET', '/attendance/summary'),
        widget.session.request('GET', '/company-settings'),
      ]);
      return {'summary': result[0], 'company': result[1]};
    },
    builder: (context, data, reload) {
      final summary = data['summary'] as Json;
      final company = data['company'] as Json;
      final checkout = summary['todayStatus'] == 'Working';
      final completed = summary['todayStatus'] == 'Completed';
      final distance = position == null
          ? null
          : Geolocator.distanceBetween(
              position!.latitude,
              position!.longitude,
              (company['latitude'] as num).toDouble(),
              (company['longitude'] as num).toDouble(),
            );
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SectionTitle(
            'Chấm công ${checkout ? 'ra' : 'vào'}',
            subtitle:
                '${company['officeName']} • Bán kính ${company['radiusMeters']} m',
            trailing: widget.session.manager
                ? IconButton(
                    tooltip: 'Phát QR chấm công',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => QrIssueScreen(session: widget.session),
                      ),
                    ),
                    icon: const Icon(Icons.qr_code_2, size: 32),
                  )
                : null,
          ),
          if (!completed) _progress(checkout),
          if (completed)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Row(
                  children: [
                    Icon(Icons.task_alt, color: Colors.teal, size: 32),
                    SizedBox(width: 16),
                    Expanded(child: Text('Bạn đã hoàn tất chấm công hôm nay.')),
                  ],
                ),
              ),
            ),
          if (!checkout)
            _step(
              '01',
              'Quét mã tại văn phòng',
              qrToken == null
                  ? 'Mã QR có thời hạn do quản lý cung cấp.'
                  : 'Đã quét QR. Máy chủ sẽ kiểm tra thời hạn khi gửi.',
              Icons.qr_code_scanner,
              () => scan(),
              qrToken == null ? 'Mở camera quét QR' : 'Quét lại',
              ready: qrToken != null,
              disabled: submitting,
            ),
          _step(
            '02',
            'Xác nhận vị trí GPS',
            position == null
                ? 'Cho phép vị trí chính xác. Sai số tối đa ${company['maxAccuracyMeters']} m.'
                : '${position!.latitude.toStringAsFixed(6)}, ${position!.longitude.toStringAsFixed(6)}\nCách văn phòng ${distance!.toStringAsFixed(0)} m • Sai số ±${position!.accuracy.toStringAsFixed(0)} m',
            Icons.my_location,
            locate,
            locating ? 'Đang lấy vị trí…' : 'Lấy vị trí hiện tại',
            ready: position != null,
            disabled: locating || submitting,
          ),
          _step(
            '03',
            'Đo chuyển động thiết bị',
            motionScore != null
                ? 'RMS gia tốc ${motionScore!.toStringAsFixed(3)} m/s² • $samples mẫu'
                : measuring
                ? 'Đang đo trong 3 giây… $samples mẫu\nX ${latest?.x.toStringAsFixed(2) ?? '—'} • Y ${latest?.y.toStringAsFixed(2) ?? '—'} • Z ${latest?.z.toStringAsFixed(2) ?? '—'} m/s²'
                : 'Đọc gia tốc không gồm trọng lực trong 3 giây. Có thể di chuyển nhẹ điện thoại để xem cảm biến.',
            Icons.sensors,
            measure,
            measuring ? 'Đang đo…' : 'Đo chuyển động 3 giây',
            ready: motionScore != null,
            disabled: measuring || submitting,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'GPS và cảm biến được gửi khi bạn xác nhận chấm công. Không theo dõi vị trí liên tục. Dữ liệu chuyển động là phép đo cảm biến, không phải bằng chứng chống giả mạo.',
              style: TextStyle(fontSize: 12, color: Colors.blueGrey),
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          FilledButton.icon(
            onPressed: submitting || completed ? null : () => submit(checkout),
            icon: submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle_outline),
            label: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                submitting
                    ? 'Đang gửi…'
                    : checkout
                    ? 'Xác nhận chấm công ra'
                    : 'Xác nhận chấm công vào',
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      );
    },
  );
  Widget _progress(bool checkout) {
    final steps = [
      if (!checkout) qrToken != null,
      position != null,
      motionScore != null,
    ];
    final done = steps.where((s) => s).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            done == steps.length
                ? 'Đã sẵn sàng xác nhận'
                : 'Hoàn thành $done/${steps.length} bước',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: done == steps.length ? Colors.teal : brandMuted,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: done / steps.length,
              minHeight: 8,
              backgroundColor: borderColor,
              color: done == steps.length ? Colors.teal : brandPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _step(
    String number,
    String title,
    String subtitle,
    IconData icon,
    VoidCallback action,
    String label, {
    bool ready = false,
    bool disabled = false,
  }) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(
        color: ready ? Colors.teal.withValues(alpha: .45) : borderColor,
        width: ready ? 1.5 : 1,
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ready
                  ? const IconBadge(Icons.check_rounded, color: Colors.teal)
                  : IconBadge(icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BƯỚC $number',
                      style: const TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                        color: brandMuted,
                      ),
                    ),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: brandInk,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            subtitle,
            style: const TextStyle(color: brandMuted, height: 1.4),
          ),
          const SizedBox(height: 12),
          ready
              ? OutlinedButton.icon(
                  onPressed: disabled ? null : action,
                  icon: Icon(icon),
                  label: Text(label),
                )
              : FilledButton.tonalIcon(
                  onPressed: disabled ? null : action,
                  icon: Icon(icon),
                  label: Text(label),
                ),
        ],
      ),
    ),
  );
}

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final controller = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  bool returned = false;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      title: const Text('Quét QR chấm công'),
      actions: [
        IconButton(
          tooltip: 'Đèn flash',
          onPressed: controller.toggleTorch,
          icon: const Icon(Icons.flash_on),
        ),
      ],
    ),
    body: Stack(
      children: [
        MobileScanner(
          controller: controller,
          onDetect: (capture) {
            for (final barcode in capture.barcodes) {
              final value = barcode.rawValue;
              if (value != null && value.isNotEmpty && !returned) {
                returned = true;
                Navigator.pop(context, value);
                break;
              }
            }
          },
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.no_photography_outlined,
                    color: Colors.white,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Không mở được camera. Cấp quyền camera trong cài đặt ứng dụng rồi mở lại màn hình quét.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: Geolocator.openAppSettings,
                    child: const Text('Mở cài đặt ứng dụng'),
                  ),
                ],
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              'Đưa mã QR do quản lý phát vào giữa camera.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
      ],
    ),
  );
}

class QrIssueScreen extends StatefulWidget {
  final Session session;
  const QrIssueScreen({super.key, required this.session});
  @override
  State<QrIssueScreen> createState() => _QrIssueScreenState();
}

class _QrIssueScreenState extends State<QrIssueScreen> {
  Json? qr;
  String? error;
  bool busy = false;
  Timer? timer;
  int get seconds => qr == null
      ? 0
      : math.max(
          0,
          DateTime.parse(qr!['expiresAtUtc'].toString())
              .difference(DateTime.now().toUtc())
              .inSeconds,
        );
  @override
  void initState() {
    super.initState();
    issue();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> issue() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.session.request('POST', '/attendance/qr');
      if (mounted) {
        setState(() {
          qr = result as Json;
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('QR chấm công')),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Quét để bắt đầu ca làm',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            if (qr != null && seconds > 0)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: QrImageView(
                    data: qr!['token'].toString(),
                    size: math.min(300, MediaQuery.sizeOf(context).width - 100),
                    backgroundColor: Colors.white,
                  ),
                ),
              )
            else
              const SizedBox(
                height: 250,
                child: Center(
                  child: Icon(
                    Icons.qr_code_2,
                    size: 160,
                    color: Colors.blueGrey,
                  ),
                ),
              ),
            const SizedBox(height: 20),
            Text(
              seconds > 0
                  ? 'Mã còn hiệu lực $seconds giây'
                  : 'Mã đã hết hạn hoặc chưa được tạo',
              style: TextStyle(
                color: seconds > 0 ? Colors.teal : Colors.deepOrange,
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(error!, style: const TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: busy ? null : issue,
              icon: const Icon(Icons.refresh),
              label: Text(busy ? 'Đang tạo…' : 'Tạo mã QR mới'),
            ),
            const SizedBox(height: 20),
            const Text(
              'Chỉ phát mã tại nơi làm việc. Máy chủ kiểm tra chữ ký, thời hạn và vị trí khi nhân viên chấm công.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );
}
