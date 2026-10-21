# Tên project Attendance

Tên hiển thị của ứng dụng là **Chấm công Hữu Duyên**. Tên kỹ thuật có cả chức năng `Attendance` và tên cá nhân theo yêu cầu của đề.

| Thành phần | Tên hiện tại |
|---|---|
| Flutter | `NguyenAnhDung.Attendance.Mobile` |
| Dart package | `nguyen_anh_dung_attendance` |
| ASP.NET Core API | `NguyenAnhDung.Attendance.Api` |
| Backend tests | `NguyenAnhDung.Attendance.Api.Tests` |
| Solution | `NguyenAnhDung.Attendance.sln` |
| Database | `NguyenAnhDungAttendance` |

Máy đang phát triển đã sao lưu SQL Server rồi đổi tên database bằng `ALTER DATABASE ... MODIFY NAME`. Số bản ghi trước và sau khớp nhau: 2 tài khoản, 1 đơn từ; các bảng phòng ban, ca và công chưa có bản ghi ở thời điểm đổi tên. Tài khoản và mật khẩu hiện có tiếp tục sử dụng được. Database nằm trong Docker volume đang dùng `nguyenanhdung-development_sql_data`.

Các máy mới cài dùng README như bình thường. Với máy đã dùng database tên cũ `NguyenAnhDung`, dừng Web API, sao lưu database rồi chạy trong SQL Server Management Studio hoặc công cụ SQL tương đương:

```sql
USE master;
GO
ALTER DATABASE [NguyenAnhDung] MODIFY NAME = [NguyenAnhDungAttendance];
GO
```

Chỉ chạy khi database nguồn tồn tại và chưa có database đích. Nếu đã có cả hai, kiểm tra dữ liệu của từng database trước khi chọn cách chuyển đổi. Sau đó chạy lại `infra/Start-Api.ps1`.

Android applicationId và iOS bundle identifier tiếp tục nhận diện cùng ứng dụng đã cài để có thể cập nhật APK bằng `adb install -r`. Sau thay đổi tên định danh Web API, đăng nhập lại trong app để nhận phiên mới.
