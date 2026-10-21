# NguyenAnhDung.Attendance.Mobile

Ứng dụng Flutter **Chấm công Hữu Duyên** của **Nguyên Anh Dũng – nhóm Hữu Duyên**, package Dart `nguyen_anh_dung_attendance`. Kết nối trực tiếp ASP.NET Core API trong thư mục `../NguyenAnhDung.Attendance.Api`. Không có tài khoản, OTP hoặc dữ liệu chấm công giả trong giao diện.

## Chạy ứng dụng

Cần Flutter stable (đã kiểm tra bằng Flutter 3.47.5 / Dart 3.13.4), Android Studio + Android SDK hoặc macOS + Xcode cho iOS.

```powershell
flutter pub get
# Android giả lập
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5080/api
# Điện thoại thật cùng Wi-Fi với máy chạy API
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:5080/api
```

Có thể đổi URL bằng biểu tượng bánh răng tại màn hình đăng nhập. URL phải kết thúc bằng `/api`. Tài khoản cần xác thực email, sau đó đăng nhập bằng tên đăng nhập/mật khẩu và mã OTP qua email. Admin mở thẳng trang quản trị; nhân viên mở Dashboard cá nhân. Vai trò Manager dành cho người xét duyệt và phát QR; server luôn kiểm tra quyền.

HTTP chỉ được bật trong cấu hình **Debug** trên Android/iOS để gọi API LAN. Bản Release cần URL HTTPS với chứng chỉ hợp lệ. Chạy `flutter build apk --debug` để tạo APK phục vụ thuyết trình. Không dùng cấu hình ký debug để phát hành ứng dụng chính thức.

## Ba nhóm chức năng nâng cao

- **b — Chia sẻ vị trí:** lấy GPS khi người dùng nhấn nút, hiển thị tọa độ/khoảng cách/sai số rồi gửi cùng lượt công. Server kiểm tra bán kính và sai số. Không theo dõi nền.
- **d — Đo chuyển động:** đọc user accelerometer (đã loại trọng lực) trong 3 giây, hiển thị trực tiếp X/Y/Z và số mẫu; lưu RMS `sqrt(mean(x²+y²+z²))` đơn vị m/s². Nếu không có dữ liệu, hiển thị lỗi; không thay bằng số giả. Dữ liệu này không chứng minh chống giả mạo.
- **e — QR:** quản trị/quản lý phát mã ký có thời hạn; nhân viên dùng camera quét. Server kiểm tra chữ ký, mục đích, thời hạn. Vân tay và QR cùng thuộc nhóm e, không tính là hai nhóm.

Trên điện thoại thật, cấp quyền Camera và Vị trí chính xác. iOS có mô tả quyền Chuyển động và Mạng nội bộ. Nếu quyền bị chặn, mở cài đặt ứng dụng để cấp lại. Giả lập có thể thiếu cảm biến/camera; cần thử ba tính năng này trên điện thoại thật. Cấu hình vị trí văn phòng và phân ca cho nhân viên trước khi chấm công.

## Các màn hình

- Đăng ký → xác thực email / gửi lại mã → tên đăng nhập + mật khẩu → OTP.
- Dashboard: trạng thái trong ngày, ngày công, giờ làm, đi muộn, thiếu giờ ra.
- Chấm công: QR, GPS và gia tốc, xác nhận vào/ra. Quản lý có màn hình phát QR đếm ngược.
- Lịch sử: lọc ngày, xem giờ công/GPS/chuyển động; quản lý xem báo cáo toàn đội.
- Đơn từ: tạo, đọc, sửa, xóa đơn đang chờ; người quản lý phê duyệt/từ chối kèm ghi chú. Server chặn tự duyệt.
- Admin: CRUD nhân viên/phòng ban/ca làm; phân quyền, phân ca, khóa tài khoản; thiết lập văn phòng và thời hạn QR.
- Trợ lý bổ sung công: phát hiện ngày cũ thiếu giờ ra và điền sẵn đề xuất Correction; người dùng bắt buộc điền giờ thực tế/lý do rồi gửi để người quản lý xem xét. Duyệt đơn không tự sửa lịch sử công. Đây là điểm khác biệt đề xuất của đồ án, không khẳng định chưa có app khác làm.

Token và API URL lưu bằng platform secure storage; mật khẩu/OTP không lưu vào thiết bị. API trả 401 sẽ xóa phiên và quay về đăng nhập. 403 hiển thị lỗi quyền của máy chủ. Có trạng thái tải, danh sách trống, lỗi và thử lại. Dữ liệu thời gian được hiển thị UTC+7.

## Kiểm tra

```powershell
flutter analyze
flutter test
flutter build apk --debug
```

Các kiểm thử dùng HTTP mock để xác nhận hợp đồng request, Bearer token, xóa phiên khi 401, giữ phiên khi 403, kiểm tra URL API, kiểm tra form trước khi gọi mạng, và màn hình vào ứng dụng theo Admin/Employee. Không thay thế kiểm thử tích hợp SMTP, SQL Server và phần cứng trên điện thoại.
