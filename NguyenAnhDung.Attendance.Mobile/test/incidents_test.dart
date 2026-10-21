import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nguyen_anh_dung_attendance/core.dart';
import 'package:nguyen_anh_dung_attendance/incidents.dart';
import 'package:nguyen_anh_dung_attendance/main.dart';

Json participant(String id, String employeeId, {String status = 'Pending'}) => {
  'id': id,
  'employeeId': employeeId,
  'employeeName': 'Nhân viên $employeeId',
  'username': employeeId,
  'firstAttemptAtUtc': '2026-10-21T01:01:00Z',
  'lastAttemptAtUtc': '2026-10-21T01:04:00Z',
  'attemptCount': 2,
  'status': status,
  'reviewNote': status == 'Pending' ? null : 'Đã kiểm tra sự cố',
  'reviewerName': status == 'Pending' ? null : 'Quản lý',
  'reviewedAtUtc': status == 'Pending' ? null : '2026-10-21T02:00:00Z',
};

Json detail(List<Json> participants) => {
  'id': 'incident-1',
  'errorCode': 'OutsideOffice',
  'errorLabel': 'Ngoài phạm vi văn phòng',
  'officeName': 'Văn phòng Hữu Duyên',
  'firstOccurredAtUtc': '2026-10-21T01:01:00Z',
  'lastOccurredAtUtc': '2026-10-21T01:04:00Z',
  'affectedEmployeeCount': participants.length,
  'pendingCount': participants.where((p) => p['status'] == 'Pending').length,
  'status': participants.any((p) => p['status'] == 'Pending')
      ? 'Open'
      : 'Resolved',
  'myReviewStatus': null,
  'participants': participants,
};

http.Response jsonResponse(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Session sessionFor(String role, MockClient client) => Session(client: client)
  ..token = 'test-session'
  ..user = {'id': 'self', 'role': role};

Future<void> reveal(WidgetTester tester, Finder finder) => tester
    .scrollUntilVisible(finder, 280, scrollable: find.byType(Scrollable).first);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'Employee sees own incident and cannot review other participants',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = sessionFor(
        'Employee',
        MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/attendance-incidents/incident-1');
          return jsonResponse(
            detail([
              participant('p-self', 'self'),
              participant('p-other', 'private-other'),
            ]),
          );
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(1.5)),
            child: child!,
          ),
          home: IncidentDetailScreen(
            session: session,
            incidentId: 'incident-1',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Nhân viên self (Bạn)'));
      expect(find.text('Nhân viên self (Bạn)'), findsOneWidget);
      expect(find.text('@private-other'), findsNothing);
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(find.byKey(const ValueKey('incident-approve')), findsNothing);
      expect(find.byKey(const ValueKey('incident-review-note')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets('Manager selects pending others, validates note and posts once', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pending = participant('p-other', 'other');
    final own = participant('p-self', 'self');
    final reviewed = participant('p-done', 'done', status: 'Rejected');
    final response = Completer<http.Response>();
    var posts = 0;
    final session = sessionFor(
      'Manager',
      MockClient((request) async {
        if (request.method == 'GET') {
          return jsonResponse(detail([pending, own, reviewed]));
        }
        posts++;
        expect(request.url.path, '/api/attendance-incidents/incident-1/review');
        expect(request.headers['Authorization'], 'Bearer test-session');
        expect(jsonDecode(request.body), {
          'participantIds': ['p-other'],
          'status': 'Approved',
          'reviewNote': 'Đã xác minh lỗi GPS tại văn phòng',
        });
        return response.future;
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: IncidentDetailScreen(session: session, incidentId: 'incident-1'),
      ),
    );
    await tester.pumpAndSettle();
    final checkbox = find.byKey(const ValueKey('participant-p-other'));
    expect(tester.widget<CheckboxListTile>(checkbox).value, isFalse);
    expect(find.byKey(const ValueKey('participant-p-self')), findsNothing);
    expect(find.byKey(const ValueKey('participant-p-done')), findsNothing);
    final approve = find.byKey(const ValueKey('incident-approve'));
    await reveal(tester, approve);
    expect(tester.widget<FilledButton>(approve).onPressed, isNull);
    await reveal(tester, checkbox);
    await tester.tap(checkbox);
    await tester.pump();
    final note = find.byKey(const ValueKey('incident-review-note'));
    await reveal(tester, note);
    await tester.enterText(note, 'abc');
    await reveal(tester, approve);
    await tester.tap(approve);
    await tester.pump();
    expect(find.text('Ghi chú cần từ 5 đến 1000 ký tự.'), findsOneWidget);
    expect(posts, 0);
    await tester.enterText(note, '  Đã xác minh lỗi GPS tại văn phòng  ');
    await tester.tap(approve);
    await tester.pump();
    expect(posts, 1);
    expect(tester.widget<FilledButton>(approve).onPressed, isNull);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    response.complete(
      jsonResponse(
        detail([
          {
            ...pending,
            'status': 'Approved',
            'reviewNote': 'Đã xác minh lỗi GPS tại văn phòng',
            'reviewerName': 'Quản lý',
          },
          own,
          reviewed,
        ]),
      ),
    );
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Đã lưu kết quả xét giải trình.'));
    expect(find.text('Đã lưu kết quả xét giải trình.'), findsOneWidget);
    expect(find.byKey(const ValueKey('incident-approve')), findsNothing);
    expect(posts, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });

  testWidgets('Rejected request keeps selection and shows server conflict', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = sessionFor(
      'Admin',
      MockClient((request) async {
        if (request.method == 'GET') {
          return jsonResponse(detail([participant('p-other', 'other')]));
        }
        expect(jsonDecode(request.body)['status'], 'Rejected');
        return jsonResponse({
          'message': 'Sự cố đã được người khác xét duyệt.',
        }, 409);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: IncidentDetailScreen(session: session, incidentId: 'incident-1'),
      ),
    );
    await tester.pumpAndSettle();
    final checkbox = find.byKey(const ValueKey('participant-p-other'));
    await tester.tap(checkbox);
    await tester.pump();
    final note = find.byKey(const ValueKey('incident-review-note'));
    await reveal(tester, note);
    await tester.enterText(note, 'Chưa đủ thông tin để chấp nhận');
    final reject = find.byKey(const ValueKey('incident-reject'));
    await reveal(tester, reject);
    await tester.tap(reject);
    await tester.pumpAndSettle();
    expect(find.text('Sự cố đã được người khác xét duyệt.'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(reject).onPressed, isNotNull);
    await reveal(tester, checkbox);
    expect(tester.widget<CheckboxListTile>(checkbox).value, isTrue);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });

  testWidgets('Incident list retries errors and shows real empty state', (
    tester,
  ) async {
    var calls = 0;
    final session = sessionFor(
      'Employee',
      MockClient((request) async {
        expect(request.url.path, '/api/attendance-incidents');
        calls++;
        return calls == 1
            ? jsonResponse({'message': 'Không thể tải sự cố.'}, 500)
            : jsonResponse([]);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(home: IncidentsScreen(session: session)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Không thể tải sự cố.'), findsOneWidget);
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(find.text('Chưa có sự cố chấm công được ghi nhận.'), findsOneWidget);
    expect(calls, 2);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });

  testWidgets('401 on a pushed detail route clears private navigation', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({'accessToken': 'old-session'});
    var detailCalls = 0;
    final incident = detail([participant('p-self', 'self')]);
    final session = Session(
      client: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/auth/me')) {
          return jsonResponse({
            'id': 'self',
            'role': 'Employee',
            'fullName': 'Dũng',
            'email': 'test@example.com',
          });
        }
        if (path.endsWith('/attendance/summary')) {
          return jsonResponse({
            'todayStatus': 'NotCheckedIn',
            'totalDaysThisMonth': 0,
            'lateDaysThisMonth': 0,
            'totalHoursThisMonth': 0,
            'missingCheckoutCount': 0,
          });
        }
        if (path.endsWith('/attendance-incidents/incident-1')) {
          detailCalls++;
          return detailCalls == 1
              ? jsonResponse(incident)
              : jsonResponse({
                  'message': 'Phiên đã hết hạn trên máy chủ.',
                }, 401);
        }
        if (path.endsWith('/attendance-incidents')) {
          return jsonResponse([incident]);
        }
        return jsonResponse([]);
      }),
    );
    await tester.pumpWidget(AttendanceApp(session: session));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Sự cố chấm công'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xem chi tiết →'));
    await tester.pumpAndSettle();
    expect(find.text('Chi tiết sự cố'), findsOneWidget);
    await tester.tap(find.byTooltip('Làm mới sự cố'));
    await tester.pumpAndSettle();
    expect(find.text('Chào ngày làm việc mới'), findsOneWidget);
    expect(find.text('Chi tiết sự cố'), findsNothing);
    expect(find.text('Nhân viên self (Bạn)'), findsNothing);
    expect(session.user, isNull);
    expect(session.token, isNull);
    expect(await session.storage.read(key: 'accessToken'), isNull);
    expect(
      find.text('Phiên đã hết hạn. Vui lòng đăng nhập lại.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
