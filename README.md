# Chấm công Hữu Duyên — NguyenAnhDung Attendance

Đồ án nhóm **Hữu Duyên**, tên hiển thị **Chấm công Hữu Duyên**. Project dùng tên theo chức năng `Attendance`, kèm tên cá nhân **Nguyên Anh Dũng** để đáp ứng yêu cầu của đề: `NguyenAnhDung.Attendance.Mobile`, `NguyenAnhDung.Attendance.Api`, database `NguyenAnhDungAttendance`. Ứng dụng Flutter kết nối ASP.NET Core Web API (.NET 10) và SQL Server. Vai trò nghiệp vụ: `Admin`, `Manager`, `Employee`; ứng dụng chấm công không có nghiệp vụ khách hàng.

Ba mục nâng cao chọn để thuyết trình là **b — chia sẻ vị trí**, **d — đo chuyển động bằng gia tốc kế**, **e — quét QR**. QR và vân tay cùng thuộc mục e, không được tính thành hai mục. Chia sẻ vị trí ở đây là gửi tọa độ lúc chấm công, không phải theo dõi nền liên tục. Chuyển động là số đo cảm biến, không phải chứng cứ chống giả mạo.

## Cấu trúc

| Thư mục | Nội dung |
|---|---|
| `NguyenAnhDung.Attendance.Mobile` | Flutter, giao diện tiếng Việt và chức năng điện thoại |
| `NguyenAnhDung.Attendance.Api` | Xác thực email/OTP, phân quyền, CRUD, chấm công |
| `NguyenAnhDung.Attendance.Api.Tests` | Kiểm thử API/quy tắc nghiệp vụ với SQLite in-memory |
| `infra` | SQL Server + Mailpit dành cho phát triển và script cấu hình local |
| `docs/DEMO.md` | Kịch bản demo, ma trận yêu cầu và biên bản kiểm thử |
| `docs/INCIDENTS.md` | Tính năng tự đề xuất: phát hiện và xử lý sự cố chấm công tập thể |
| `docs/ARCHITECTURE.md` | Sơ đồ xác thực/ER, luồng b–d–e và ma trận quyền để thuyết trình |
| `API_CONTRACT.md` | Định dạng request/response giữa hai source |

## Chuẩn bị máy

- Flutter stable có Dart SDK đáp ứng `pubspec.yaml`; Android Studio, Android SDK và emulator hoặc điện thoại Android bật USB debugging.
- .NET **10 SDK**; lệnh `dotnet --list-sdks` phải có bản 10.x.
- Docker Desktop chạy **Linux containers**, Docker Compose v2; SQL Server container dùng máy x64, nên dành tối thiểu 4 GB RAM cho Docker.
- Git và PowerShell. Mở terminal tại thư mục chứa README này.

Kiểm tra `flutter doctor`, `flutter devices`, `dotnet --info`, `docker version`. Bộ source iOS có thể phát triển tiếp trên macOS với Xcode; cần kiểm thử iPhone riêng. Bản demo ưu tiên Android.

## 1. Tạo cấu hình riêng trên mỗi máy

Chạy lệnh sau với email và tên đăng nhập admin của thành viên đang cài. Thay ví dụ email bằng địa chỉ của bạn nếu dùng SMTP thật.

```powershell
.\infra\Initialize-Development.ps1 -AdminUsername dung.admin -AdminEmail dung@example.com
```

Script tạo `infra/.env` với mật khẩu SQL, khóa JWT và mật khẩu admin **ngẫu nhiên**. Không có tài khoản/mật khẩu đăng nhập cố định trong source. Mở `infra/.env` bằng trình soạn thảo để đọc `BOOTSTRAP_ADMIN_PASSWORD` cho lần đăng nhập đầu. File này đã được gitignore; mỗi máy giữ cấu hình riêng, không gửi vào nhóm chat hoặc commit Git. `.env.example` chỉ mô tả các biến, không chứa secret dùng được.

Nếu PowerShell chặn script trên máy của bạn, có thể chạy bằng `powershell -ExecutionPolicy Bypass -File .\infra\Initialize-Development.ps1 -AdminUsername dung.admin -AdminEmail dung@example.com`; tùy chọn chỉ áp dụng cho tiến trình được mở. Script từ chối ghi đè `.env` đã tồn tại.

## 2. Chạy SQL Server và hộp thư thử nghiệm

```powershell
docker compose --env-file infra/.env -f infra/compose.yaml up -d
docker compose --env-file infra/.env -f infra/compose.yaml ps
```

Đợi `sqlserver` ở trạng thái healthy, lần đầu có thể mất vài phút tải image/khởi tạo. SQL nghe tại `127.0.0.1:1433`. Mailpit nhận SMTP tại `127.0.0.1:1025`; mở **http://localhost:8025** trên máy chạy API để đọc email xác thực và OTP. Mailpit giữ thư để demo local, **không gửi thư ra hộp thư Internet của người nhận**. Điện thoại chỉ gọi API; không cần mở cổng SQL hay Mailpit cho điện thoại.

Compose bind tất cả các cổng hạ tầng vào loopback. Không đổi sang `0.0.0.0` để chia sẻ hộp thư OTP. Dữ liệu SQL nằm trong named volume và còn sau khi `docker compose ... down`; không xóa volume khi cần giữ dữ liệu thuyết trình. Đổi `SQL_SA_PASSWORD` trong `.env` sau khi SQL đã có dữ liệu không tự đổi mật khẩu login trong database.

## 3. Chạy Web API

```powershell
.\infra\Start-Api.ps1
```

Script nạp `.env`, tạo connection string cho database **NguyenAnhDungAttendance**, bật môi trường Development rồi chạy project `NguyenAnhDung.Attendance.Api/NguyenAnhDung.Attendance.Api.csproj` tại **http://localhost:5080**. Script ưu tiên `dotnet` đã cài trên PATH; nếu không có, dùng SDK local tại `.tools/dotnet/dotnet.exe` khi thư mục này tồn tại. Máy hiện tại đã có SDK local **10.0.402**, runtime **10.0.13**; đây là công cụ riêng của máy, không nằm trong source Git. Khi dùng SDK local, script đặt `DOTNET_ROOT`, `DOTNET_CLI_HOME` và `NUGET_PACKAGES` trong tiến trình chạy, rồi khôi phục sau khi kết thúc. Thành viên khác chỉ cần cài .NET 10 SDK thông thường.

Kiểm tra **http://localhost:5080/health**; các endpoint ứng dụng có tiền tố `/api`. API dùng `EnsureCreated` để tạo schema lần đầu khi `Database__Initialize=true`, không sử dụng EF migrations trong bản đồ án này. Bản cập nhật sự cố tập thể có script nâng cấp bổ sung ba bảng trên database cũ, không tạo lại các bảng nghiệp vụ. Sao lưu trước khi cập nhật; `EnsureCreated` không tự nâng cấp các thay đổi schema khác.

Có sẵn [script SQL Server NguyenAnhDungAttendance.sql](NguyenAnhDung.Attendance.Api/database/NguyenAnhDungAttendance.sql) xuất từ model EF Core: 10 bảng và 6 unique index. Script tạo/chọn database `NguyenAnhDungAttendance` nếu chưa có, rồi tạo bảng; chỉ chạy **một lần trên database mới**, không phải script migrations cho database đã có schema. Có thể mở script bằng SSMS hoặc công cụ chạy SQL Server hỗ trợ `GO`. Không cần chạy script nếu để API tự tạo schema. Script không chứa tài khoản hoặc dữ liệu mẫu; với `Database__Initialize=true`, API bổ sung bản ghi cấu hình công ty lúc startup và chỉ tạo Admin khi bật BootstrapAdmin rõ ràng.

Máy hiện tại đã đổi tên database cũ và giữ nguyên tài khoản, đơn từ. Thành viên đã chạy bản source cũ xem [ghi chú đổi tên](docs/RENAMING.md) trước khi dùng bản mới.

Admin khởi tạo được xác thực email sẵn, vẫn phải nhập OTP khi đăng nhập. Sau lần tạo thành công, đổi `BOOTSTRAP_ADMIN_ENABLED=false` trong `.env`, bỏ giá trị `BOOTSTRAP_ADMIN_PASSWORD` rồi khởi động lại API. Những lần đăng ký/tạo nhân viên tiếp theo phải xác thực qua email.

Để chạy lệnh .NET trực tiếp thay vì script, đặt các biến môi trường cùng tên sau (hoặc dùng user-secrets cho Development):

| Key ASP.NET Core | Nguồn trong `infra/.env` |
|---|---|
| `ConnectionStrings__DefaultConnection` | Script tạo từ `SQL_SA_PASSWORD`, server tcp:127.0.0.1,1433, DB NguyenAnhDungAttendance |
| `Jwt__Key` | `JWT_KEY`, tối thiểu 32 byte |
| `Database__Initialize` | `true` trong script phát triển |
| `BootstrapAdmin__Enabled/Username/Email/Password/FullName` | Các key `BOOTSTRAP_ADMIN_*` tương ứng |
| `Email__DeliveryMethod` | `EMAIL_DELIVERY_METHOD`, `Smtp` hoặc `Console` |
| `Email__Host/Port/Username/Password/FromAddress/UseSsl` | Các key `EMAIL_*` tương ứng |

`Console` chỉ dùng được trong Development: mã được ghi rõ vào log backend để kiểm thử, không được trả trong response API. Muốn chứng minh yêu cầu gửi email khi thuyết trình, dùng Mailpit qua SMTP hoặc SMTP thật.

## 4. Chạy Flutter

Mở terminal thứ hai:

```powershell
Set-Location NguyenAnhDung.Attendance.Mobile
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5080/api
```

`10.0.2.2` là địa chỉ để **Android Emulator** truy cập máy chạy API; `localhost` trên điện thoại là chính điện thoại. App có hiển thị địa chỉ API đang dùng để kiểm tra cấu hình. **Nếu bản app đã lưu địa chỉ API trước đó, cấu hình đã lưu sẽ ưu tiên hơn `--dart-define`**: mở biểu tượng bánh răng tại màn hình đăng nhập để đổi địa chỉ. Chạy `flutter devices` rồi thêm `-d <device-id>` nếu có nhiều thiết bị. Camera, GPS và gia tốc kế cần được cấp quyền; dùng điện thoại thật để demo ba chức năng nâng cao đáng tin cậy hơn. Emulator có thể cần đặt vị trí giả lập phù hợp với tọa độ công ty để kiểm thử geofence.

### Điện thoại thật qua Wi-Fi

Cho máy tính và điện thoại vào cùng mạng, lấy IPv4 của máy tính bằng `ipconfig`, ví dụ `192.168.1.20`. Dừng API cũ và chạy:

```powershell
.\infra\Start-Api.ps1 -ListenUrl http://0.0.0.0:5080
```

Tại terminal trong `NguyenAnhDung.Attendance.Mobile`:

```powershell
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:5080/api
```

Thay IP ví dụ bằng IP thật. Mở `http://<IP-may-tinh>:5080/health` từ trình duyệt điện thoại trước. Nếu Windows Firewall chặn và đây là mạng Private tin cậy, có thể mở PowerShell **Run as administrator** và tạo rule giới hạn mạng local:

```powershell
New-NetFirewallRule -DisplayName "NguyenAnhDung API dev" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 5080 -Profile Private -RemoteAddress LocalSubnet
```

Đóng rule sau buổi demo bằng `Remove-NetFirewallRule -DisplayName "NguyenAnhDung API dev"`. HTTP này chỉ phục vụ phát triển trong mạng tin cậy; triển khai thật cần HTTPS. Không mở cổng 1433, 1025 hoặc 8025 cho LAN/Internet.

### Gửi OTP tới hộp thư thật

Thay các giá trị `EMAIL_*` trong `.env` bằng thông tin nhà cung cấp SMTP: `EMAIL_DELIVERY_METHOD=Smtp`, host, port, username, mật khẩu SMTP/app password và địa chỉ From được nhà cung cấp cho phép. Với server STARTTLS thường dùng cổng 587, đặt `EMAIL_USE_SSL=true`; kiểm tra cấu hình thực tế của nhà cung cấp. Khởi động lại API sau khi sửa. Không dùng mật khẩu SMTP trong code Flutter. Điện thoại nhận email bằng ứng dụng email bình thường; Mailpit local không chuyển tiếp những thư đã giữ sang Internet.

## Luồng sử dụng

1. Admin đăng nhập bằng username + password, lấy OTP từ email và xác nhận.
2. Admin tạo phòng ban, ca làm, cấu hình tọa độ/vùng chấm công. Tạo tài khoản nhân viên hoặc để nhân viên đăng ký email.
3. Nhân viên xác thực email; admin gán phòng ban và ca làm cho nhân viên trước khi chấm công. Có thể cấp vai trò Manager cho người duyệt đơn.
4. Admin/Manager tạo QR ngắn hạn, hiển thị cho nhân viên quét bằng camera. Nhân viên bật vị trí, đo chuyển động rồi chấm vào. API kiểm tra QR, bán kính và độ chính xác GPS.
5. Nhân viên chấm ra, xem lịch sử và tạo/sửa/xóa đơn khi còn Pending. Admin/Manager duyệt theo quyền; không tự duyệt đơn của chính mình.
6. Nếu có bản ghi ngày trước thiếu chấm ra, ứng dụng gợi ý tạo đơn bổ sung (`Correction`). Người dùng phải gửi đơn và quản lý xét duyệt; phê duyệt đơn không tự sửa giờ chấm công.

7. Khi máy chủ nhận cùng lỗi QR/GPS từ ít nhất 3 nhân viên khác nhau trong 5 phút với cùng cấu hình văn phòng, app ghi nhận nghi sự cố tập thể. Mở **Sự cố chấm công** để xem danh sách; Admin/Manager chọn người và duyệt/từ chối giải trình kèm lý do. Nhân viên chỉ xem thông tin của mình. Quyết định không tự đổi giờ công hoặc trạng thái đi trễ.

Tính năng nhóm tự đề xuất chính là [phát hiện và xử lý sự cố chấm công tập thể](docs/INCIDENTS.md). Gợi ý bổ sung công vẫn được giữ. Chưa có cơ sở để khẳng định mọi ứng dụng trên thị trường đều chưa có quy trình tương tự; tài liệu tính năng nêu rõ phạm vi khảo sát. Xem [kịch bản demo và checklist](docs/DEMO.md), [sơ đồ kiến trúc và ma trận quyền](docs/ARCHITECTURE.md).

## Kiểm tra và xử lý lỗi

```powershell
dotnet build NguyenAnhDung.Attendance.Api/NguyenAnhDung.Attendance.Api.csproj
dotnet test NguyenAnhDung.Attendance.sln
```

Backend tests dùng SQLite in-memory để chạy độc lập SQL Server/SMTP bên ngoài. Provider này không chứng minh được rowversion, khóa giao dịch hoặc tranh chấp đồng thời của SQL Server; các trường hợp đó vẫn cần nghiệm thu với SQL Server thật.

Trong thư mục Flutter, chạy `flutter analyze`, `flutter test` và `flutter build apk --debug`. Hiện tại Flutter analyze không có vấn đề, **12/12 tests đạt** và đã tạo [APK debug](NguyenAnhDung.Attendance.Mobile/build/app/outputs/flutter-apk/app-debug.apk) (207.086.342 byte, khoảng 197 MiB). APK nằm trong thư mục build bị gitignore; máy khác cần tự build hoặc nhận file APK riêng. Backend đã build cả API và test project qua `dotnet test NguyenAnhDung.Attendance.sln --no-restore`, **25/25 tests đạt**, bao gồm kiểm tra schema do SQL Server provider sinh mà không kết nối database. Sự cố tập thể đã được thử thêm trên SQL Server + SMTP Mailpit thật: ngưỡng ba người, quyền xem, duyệt/từ chối theo nhóm, chống duyệt lại và giữ nguyên bảng công/đơn từ đều đạt; APK mới đã mở danh sách/chi tiết trên Small_Phone. Xem [biên bản riêng](docs/INCIDENTS.md).

Trên máy hiện tại đã chạy SQL Server 2022 và Mailpit qua Docker, tạo database/Admin thành công và kiểm tra luồng mật khẩu → SMTP OTP → JWT → hồ sơ/Dashboard với SQL Server thật. SMTP trong lần chạy này là hộp thư thử nghiệm Mailpit; việc gửi ra Gmail hoặc nhà cung cấp email bên ngoài chưa được nghiệm thu. Camera, GPS, gia tốc kế và các tình huống tranh chấp dữ liệu vẫn cần kiểm tra riêng. Kết quả chi tiết nằm trong [biên bản kiểm chứng](docs/DEMO.md).

| Hiện tượng | Kiểm tra |
|---|---|
| Không gọi được API | `/health`, IP/port và `/api` đúng; điện thoại cùng mạng; firewall; API còn chạy |
| SQL khởi động lỗi | Docker Linux containers, RAM, cổng 1433 chưa bị chiếm; `docker compose --env-file infra/.env -f infra/compose.yaml logs sqlserver` |
| SQL healthy nhưng API lỗi timeout 258 | Script dùng `tcp:127.0.0.1,1433` để kết nối đúng cổng IPv4 đã publish; tránh `localhost,1433` nếu SQL Client phân giải sai địa chỉ trên Windows |
| Không có OTP | Mailpit http://localhost:8025 khi chạy local; hoặc SMTP credential/STARTTLS/From và thư rác khi dùng SMTP thật |
| Không chấm công được | Nhân viên đã có ca, QR chưa hết hạn, đã cho quyền GPS, nằm trong bán kính và sai số cho phép |
| Camera không quét | Cấp quyền camera, thử điện thoại thật, làm mới QR đã hết hạn |
| 401 khi gọi API | Đăng nhập lại để lấy phiên mới; không sao chép token giữa thành viên |

## Tài liệu nền tảng

- [SQL Server container — Microsoft](https://learn.microsoft.com/en-us/sql/linux/quickstart-install-connect-docker?view=sql-server-ver17)
- [Mailpit Docker](https://mailpit.axllent.org/docs/install/docker/) và [cấu hình SMTP](https://mailpit.axllent.org/docs/configuration/smtp/)
- [Android Emulator networking](https://developer.android.com/studio/run/emulator-networking-address) và [Flutter networking](https://docs.flutter.dev/data-and-backend/networking)
