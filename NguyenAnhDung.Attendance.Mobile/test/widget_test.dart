import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nguyen_anh_dung_attendance/auth.dart';
import 'package:nguyen_anh_dung_attendance/core.dart';
import 'package:nguyen_anh_dung_attendance/home.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('Authenticated API uses bearer token and exact JSON payload', () async {
    final session = Session(
      client: MockClient((request) async {
        expect(request.url.path, '/api/attendance/check-in');
        expect(request.headers['Authorization'], 'Bearer secret-session');
        expect(jsonDecode(request.body), {
          'latitude': 10.5,
          'motionScore': 0.3,
        });
        return http.Response('{"id":"attendance-1"}', 200);
      }),
    );
    session.token = 'secret-session';
    final result = await session.request('POST', '/attendance/check-in', {
      'latitude': 10.5,
      'motionScore': 0.3,
    });
    expect(result['id'], 'attendance-1');
    session.dispose();
  });

  test('Expired token clears user and secure storage on 401', () async {
    FlutterSecureStorage.setMockInitialValues({'accessToken': 'expired'});
    final session = Session(
      client: MockClient(
        (_) async => http.Response('{"message":"Session expired"}', 401),
      ),
    );
    session.token = 'expired';
    session.user = {'id': 'u1', 'role': 'Employee'};
    await expectLater(
      session.request('GET', '/attendance'),
      throwsA(isA<ApiException>()),
    );
    expect(session.token, isNull);
    expect(session.user, isNull);
    expect(await session.storage.read(key: 'accessToken'), isNull);
    expect(session.notice, contains('Phiên đã hết hạn'));
    session.dispose();
  });

  test(
    '403 returns server message and retains authenticated session',
    () async {
      final session = Session(
        client: MockClient(
          (_) async => http.Response('{"message":"Forbidden"}', 403),
        ),
      );
      session.token = 'valid';
      await expectLater(
        session.request('DELETE', '/employees/1'),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 403)),
      );
      expect(session.token, 'valid');
      session.dispose();
    },
  );

  test('API URL requires HTTP(S) host and /api suffix', () async {
    final session = Session();
    await expectLater(
      session.changeBaseUrl('file:///api'),
      throwsA(isA<ApiException>()),
    );
    await expectLater(
      session.changeBaseUrl('http://localhost:5080'),
      throwsA(isA<ApiException>()),
    );
    await session.changeBaseUrl(' http://192.168.1.2:5080/api/ ');
    expect(session.baseUrl, 'http://192.168.1.2:5080/api');
    session.dispose();
  });

  testWidgets('Login validates blank fields before making network requests', (
    tester,
  ) async {
    var calls = 0;
    final session = Session(
      client: MockClient((_) async {
        calls++;
        return http.Response('{}', 400);
      }),
    );
    await tester.pumpWidget(MaterialApp(home: AuthScreen(session: session)));
    await tester.tap(find.text('Tiếp tục đăng nhập'));
    await tester.pump();
    expect(find.text('Vui lòng nhập tên đăng nhập.'), findsOneWidget);
    expect(find.text('Nhập mật khẩu.'), findsOneWidget);
    expect(calls, 0);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });

  testWidgets(
    'Password step creates challenge; only valid OTP stores session',
    (tester) async {
      final session = Session(
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (request.url.path.endsWith('/auth/login')) {
            expect(body, {'identifier': 'dung', 'password': 'Password1234'});
            return http.Response(
              jsonEncode({
                'challengeId': 'challenge-1',
                'maskedEmail': 'd***@example.com',
                'expiresAtUtc': DateTime.now()
                    .toUtc()
                    .add(const Duration(minutes: 5))
                    .toIso8601String(),
              }),
              200,
            );
          }
          expect(request.url.path, '/api/auth/verify-otp');
          expect(body, {'challengeId': 'challenge-1', 'code': '123456'});
          return http.Response(
            jsonEncode({
              'accessToken': 'verified-token',
              'user': {'id': 'u1', 'role': 'Employee', 'fullName': 'Dũng'},
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      await tester.pumpWidget(MaterialApp(home: AuthScreen(session: session)));
      await tester.enterText(find.byType(TextFormField).at(0), 'dung');
      await tester.enterText(find.byType(TextFormField).at(1), 'Password1234');
      await tester.tap(find.text('Tiếp tục đăng nhập'));
      await tester.pumpAndSettle();
      expect(session.token, isNull);
      expect(find.text('Xác nhận đăng nhập'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, '123456');
      await tester.tap(find.text('Xác nhận OTP'));
      await tester.pumpAndSettle();
      expect(
        session.token,
        'verified-token',
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .join('\n'),
      );
      expect(await session.storage.read(key: 'accessToken'), 'verified-token');
      expect(await session.storage.read(key: 'password'), isNull);
      expect(await session.storage.read(key: 'code'), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets('Admin starts on management and Employee starts on dashboard', (
    tester,
  ) async {
    for (final role in ['Admin', 'Employee']) {
      final session = Session(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/summary')) {
            return http.Response(
              '{"todayStatus":"NotCheckedIn","totalDaysThisMonth":0,"lateDaysThisMonth":0,"totalHoursThisMonth":0,"missingCheckoutCount":0}',
              200,
            );
          }
          return http.Response('[]', 200);
        }),
      );
      session.user = {
        'id': 'u1',
        'role': role,
        'fullName': 'Dũng',
        'email': 'dung@example.com',
      };
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(key: ValueKey(role), session: session),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(role == 'Admin' ? 'Trang quản trị' : 'Xin chào, Dũng'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    }
  });
}
