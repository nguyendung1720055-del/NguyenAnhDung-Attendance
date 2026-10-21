# NguyenAnhDung.Attendance.Api

ASP.NET Core 10 + Entity Framework Core SQL Server. Tên project, namespace và cơ sở dữ liệu đều chứa `NguyenAnhDung`, theo tên cá nhân **Nguyên Anh Dũng** do nhóm xác nhận. API được mô tả đầy đủ trong [API_CONTRACT.md](../API_CONTRACT.md).

## Chạy

1. Cài .NET SDK 10, SQL Server 2022+ hoặc LocalDB. Khôi phục dependency: `dotnet restore NguyenAnhDung.Attendance.Api.csproj`.
2. Cấu hình biến môi trường hoặc `dotnet user-secrets` cho project này. Không ghi bí mật vào source.
3. `dotnet run --project NguyenAnhDung.Attendance.Api.csproj` mở HTTP port 5080 trên mọi interface để điện thoại cùng mạng truy cập. Khi triển khai, đặt sau HTTPS reverse proxy và giới hạn firewall phù hợp.

API ghi log qua Console để chạy bằng tài khoản thường trên Windows/macOS/Linux; không cần quyền ghi Windows EventLog.

Các biến cấu hình:

| Biến | Ý nghĩa |
|---|---|
| `ConnectionStrings__DefaultConnection` | Connection string SQL Server; database `NguyenAnhDungAttendance` |
| `Jwt__Key` | Bí mật ngẫu nhiên riêng, ít nhất 32 byte UTF-8; bắt buộc |
| `Jwt__Issuer`, `Jwt__Audience` | Mặc định `NguyenAnhDung.Attendance.Api`, `NguyenAnhDung.Attendance.Mobile` |
| `Jwt__LifetimeMinutes` | Mặc định 60; cho phép 5–1440 |
| `Email__DeliveryMethod` | `Smtp` hoặc `Console` |
| `Email__Host`, `Email__Port` | SMTP host/port (mặc định 587) |
| `Email__Username`, `Email__Password` | Tài khoản SMTP (có thể là app password) |
| `Email__FromAddress`, `Email__FromName` | Địa chỉ và tên người gửi |
| `Email__UseSsl` | `true`: SMTP STARTTLS; bắt buộc ngoài Development |
| `ASPNETCORE_ENVIRONMENT` | `Development` khi làm bài, `Production` khi triển khai |
| `Database__Initialize` | Mặc định `true`: `EnsureCreatedAsync` tạo schema của database mới, thêm cài đặt công ty |
| `BootstrapAdmin__Enabled` | Mặc định `false`; `true` để tạo Admin ban đầu khi chưa có Admin hoạt động |
| `BootstrapAdmin__Username`, `BootstrapAdmin__Email`, `BootstrapAdmin__Password`, `BootstrapAdmin__FullName` | Thông tin Admin do người chạy cung cấp |

`appsettings.Development.json` bật rõ ràng `Console`: mã email chỉ in trong terminal với nhãn `DEVELOPMENT EMAIL ONLY`; API không trả mã. Có thể thay bằng SMTP thật hoặc Mailpit cục bộ. Production từ chối Console, cấu hình SMTP thiếu và SMTP không bật TLS. Dùng SMTP STARTTLS 587; `System.Net.Mail.SmtpClient` không hỗ trợ implicit TLS của cổng 465.

Admin bootstrap được đánh dấu đã xác thực email bởi thao tác quản trị thiết lập ban đầu; các tài khoản đăng ký/tạo từ API bắt buộc xác thực email. Không có tài khoản hay mật khẩu mặc định. Bootstrap không nâng quyền tài khoản đã tồn tại. Tắt BootstrapAdmin và bỏ mật khẩu bootstrap khỏi môi trường sau lần thiết lập đầu.

## Quy tắc dữ liệu và bảo mật

- Mọi tài khoản đi qua mật khẩu → OTP email trước khi nhận JWT. OTP 6 chữ số ngẫu nhiên bằng CSPRNG, lưu HMAC gắn với ID/purpose; hết hạn 10 phút, tối đa 5 lần nhập, chỉ dùng một lần. Gửi lại cách nhau 45 giây; mật khẩu sai 5 lần khóa 15 phút. API auth giới hạn 30 yêu cầu/phút/IP trong một tiến trình.
- Mật khẩu được băm bằng ASP.NET Core PasswordHasher (PBKDF2, 210.000 vòng). JWT kiểm tra issuer, audience, thuật toán, chữ ký, hạn và purpose. QR có audience, purpose và khóa dẫn xuất riêng, không thể dùng làm access token. Quyền và trạng thái tài khoản được đọc lại từ SQL trên mọi yêu cầu đã xác thực.
- Vai trò `Admin`, `Manager`, `Employee`; đăng ký công khai luôn tạo Employee. Admin CRUD phòng ban, ca làm, tài khoản và cài đặt. Manager xem nhân viên và duyệt đơn của Employee. Không tự duyệt đơn, tự hạ quyền/vô hiệu hóa Admin; bảo vệ Admin cuối cùng bằng transaction Serializable.
- Chấm công dùng ngày UTC+7, lưu timestamp UTC. Không hỗ trợ ca qua đêm. SQL unique index `(EmployeeId, WorkDate)` ngăn chấm vào trùng, rowversion ngăn ghi đè đồng thời khi chấm ra/duyệt đơn/xác thực mã.
- QR hết hạn theo cài đặt 15–300 giây. QR dùng chung cho nhân viên trong thời hạn; chỉ một lượt check-in/ngày/tài khoản. Geofence và độ chính xác GPS kiểm tra tại API cho cả vào và ra. Vị trí mặc định là tọa độ mẫu, Admin phải cấu hình văn phòng thực tế trước khi sử dụng.
- MotionScore là số đo cảm biến do ứng dụng gửi, **không phải** bằng chứng chống giả mạo. GPS/QR có thể bị chia sẻ hoặc giả lập; bài này chưa có attestation, chống mock-location ở mức hệ điều hành hoặc nhận diện khuôn mặt.
- Xóa nhân viên là ngừng hoạt động để giữ lịch sử. Đơn Correction có quy trình gửi/duyệt; việc duyệt **không tự dựng giờ ra** hoặc thay đổi bảng công. Không coi đơn được duyệt là bản ghi công đã sửa.
- Chỉ lưu vị trí tại thời điểm chấm công, không theo dõi nền. Email, vị trí và dữ liệu nhân sự chỉ xuất hiện qua API có phân quyền. Quy mô bài môn học: danh sách chưa phân trang, chưa có job dọn OTP hết hạn, chưa có phân phối rate limit khi chạy nhiều máy chủ.

## Schema và nâng cấp

Tính năng sự cố chấm công theo nhóm dùng ba bảng `AttendanceFailureAttempts`, `AttendanceIncidents`, `AttendanceIncidentParticipants`. Từ ba nhân viên khác nhau gặp cùng lỗi QR/GPS/phạm vi, cùng bản chụp cài đặt văn phòng trong cửa sổ năm phút theo giờ server, hệ thống tạo sự cố để quản lý duyệt giải trình theo nhóm. Nhân viên chỉ xem danh tính/giải trình của chính mình; Admin/Manager xem và duyệt từng người hoặc nhiều người, không tự duyệt. Phê duyệt chỉ ghi nhận giải trình; không đổi giờ công hay trạng thái trễ.

Khi `Database__Initialize=true`, sau `EnsureCreatedAsync`, SQL Server chạy script nhúng [Upgrade-AttendanceIncidents.sql](database/Upgrade-AttendanceIncidents.sql). Script chỉ tạo ba bảng/index còn thiếu trong transaction có khóa triển khai; không xóa/sửa bảng cũ hoặc dữ liệu hiện có. Có thể chạy script thủ công trên database đã chọn. Khi `Database__Initialize=false`, cần quản trị viên áp dụng script trước khi dùng chức năng mới. Nên backup trước nâng cấp.

Mọi lượt lỗi hợp lệ dùng thời gian server; không lưu nội dung QR hoặc vị trí của lượt lỗi. Yêu cầu sai định dạng, chưa có ca, chưa chấm vào hoặc chấm trùng không được tính. Các lượt lỗi được giữ để đối chiếu trong phạm vi đồ án; triển khai thực cần chính sách lưu trữ/xóa dữ liệu. Bằng chứng đã duyệt được giữ nguyên, không gộp các lượt lỗi mới vào nội dung đã duyệt. Bộ gom sự cố sử dụng semaphore trong một tiến trình và transaction/rowversion SQL; cần khóa phân tán nếu chạy nhiều máy chủ API.

`EnsureCreatedAsync` tạo database/schema từ EF model khi database mới hoàn toàn. Không xóa dữ liệu và không tự cập nhật schema đã tồn tại. Khi model thay đổi, dùng database phát triển riêng hoặc bổ sung EF migrations có kế hoạch. Không chạy `EnsureDeleted` trên dữ liệu thật. Tài khoản SQL chạy ứng dụng cần quyền tạo schema ở lần đầu; sau khi provision có thể tắt `Database__Initialize` và thu hẹp quyền.

Có thể xuất script DDL chính xác từ EF model mà không cần kết nối SQL hoặc thiết lập email/JWT: `dotnet run --project NguyenAnhDung.Attendance.Api.csproj -- --export-schema`. Script tạo bảng/index trong database hiện tại; nếu chạy thủ công, hãy tạo/chọn database `NguyenAnhDungAttendance` trước. File DDL không chứa tài khoản, mật khẩu hoặc dữ liệu công ty; khởi tạo app lần đầu sẽ thêm cài đặt công ty.

`GET /health` trả `healthy` nếu kết nối SQL được, ngược lại HTTP 503; không trả connection string. Endpoint này không xác nhận SMTP hoặc cảm biến điện thoại hoạt động.

## Cấu trúc

- `Controllers/`: endpoint, RBAC, CRUD, attendance và review.
- `Data/AttendanceDbContext.cs`: SQL model, foreign key Restrict, unique indexes, UTC converter.
- `Services/AuthService.cs`: đăng ký, email verification, OTP và khóa mật khẩu.
- `Services/TokenService.cs`: JWT access/QR tách purpose và ký mã OTP.
- `Services/Infrastructure.cs`: SMTP, lỗi tiếng Việt và validation dùng chung.
- `Services/DatabaseInitializer.cs`: tạo schema và Admin opt-in.

Phụ thuộc Microsoft `10.0.13` đã đối chiếu bản phát hành chính thức: [JwtBearer](https://www.nuget.org/packages/Microsoft.AspNetCore.Authentication.JwtBearer/10.0.13), [EF Core SQL Server](https://www.nuget.org/packages/Microsoft.EntityFrameworkCore.SqlServer/10.0.13).
