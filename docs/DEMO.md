# Kịch bản thuyết trình — nhóm Hữu Duyên

Tên cá nhân **Nguyên Anh Dũng**, giữ tiền tố `NguyenAnhDung` trong các project `NguyenAnhDung.Attendance.Mobile`, `NguyenAnhDung.Attendance.Api` và database `NguyenAnhDungAttendance`. Tên hiển thị **Chấm công Hữu Duyên**, đề tài **App chấm công cho nhân viên**. Đây là checklist nghiệm thu: các dòng ghi “cần kiểm chứng” là hành vi phải chạy thực tế, không phải xác nhận đã demo thành công. Ghi lại thiết bị, ngày chạy, người thử và kết quả trước khi nộp.

## Kết quả kiểm chứng hiện tại — 21/10/2026

| Kiểm tra | Kết quả đã quan sát |
|---|---|
| `flutter analyze` | Thành công: `No issues found` |
| `flutter test` | **12/12 tests passed**, có kiểm tra giao diện sự cố và xóa màn hình riêng tư khi hết phiên |
| `flutter build apk --debug` | Thành công; [app-debug.apk](../NguyenAnhDung.Attendance.Mobile/build/app/outputs/flutter-apk/app-debug.apk), 207.086.342 byte; đã cài trên Small_Phone |
| PowerShell scripts `infra` | Parser không lỗi; smoke tạo secret/nạp cấu hình/khôi phục biến môi trường đạt với `dotnet` giả lập |
| Build backend | Thành công, **0 warnings / 0 errors** |
| `dotnet test NguyenAnhDung.Attendance.sln --no-restore` | **25/25 tests passed**, gồm unit test, HTTP integration test, sự cố tập thể và SQL model regression test |
| Process Kestrel thật | Khởi động tại `127.0.0.1:5081` trong Development; GET `/api/departments` không token → 401; POST `/api/auth/register` với `{}` → 400; dừng tiến trình không có stderr |
| .NET SDK local | Đã cài 10.0.402 (runtime 10.0.13) tại `.tools/dotnet/dotnet.exe` |
| Script schema SQL Server | Đã xuất [NguyenAnhDungAttendance.sql](../NguyenAnhDung.Attendance.Api/database/NguyenAnhDungAttendance.sql) từ model EF Core; API đã tạo schema tương ứng trên SQL Server 2022 bằng EnsureCreated. Chưa chạy file SQL thủ công |
| Máy ảo Android | AVD `Small_Phone` đã mở, `emulator-5554` online; cài APK thành công và mở được màn hình đăng nhập tiếng Việt |
| Camera/GPS/gia tốc kế trên thiết bị | Chưa kiểm chứng runtime; cần điện thoại thật hoặc emulator phù hợp |
| SQL Server + SMTP Mailpit | Docker SQL Server 2022 và Mailpit healthy; API `/health` healthy tại `localhost:5080`; tạo database, singleton cấu hình và Admin thành công |
| Mật khẩu + OTP trên hệ thống local | Đăng nhập Admin → nhận OTP qua SMTP Mailpit → xác nhận OTP → nhận JWT → GET hồ sơ, cấu hình công ty và Dashboard thành công, dùng SQL Server thật |
| SMTP gửi email ra Internet | Chưa kiểm chứng Gmail hoặc nhà cung cấp email bên ngoài |
| Đổi tên Attendance | Build lại backend 19/19 tests và Flutter 7/7 tests đều đạt; APK mới đã cài cập nhật trên Small_Phone. Database mới `NguyenAnhDungAttendance` giữ nguyên 2 tài khoản, 1 đơn; đăng nhập Admin bằng mật khẩu cũ + OTP thành công |
| Nâng cấp sự cố tập thể | Backup checksum hợp lệ; thêm ba bảng và chạy lại script nâng cấp thành công. Trước thêm dữ liệu thử, giữ nguyên 4 tài khoản, 1 lượt công, 1 đơn |
| Sự cố tập thể với SQL Server + Mailpit | Tạo/xác thực/OTP ba tài khoản thử riêng; ngưỡng người thứ ba, bảo vệ thông tin nhân viên, duyệt lô nguyên tử, duyệt/từ chối/chống gửi lại đều đạt. Bảng công và đơn từ không thay đổi; tài khoản thử đã vô hiệu hóa |
| Giao diện sự cố trên Small_Phone | Mở danh sách và chi tiết dữ liệu thật; hiển thị 3 người, trạng thái Đã xử lý, thời điểm và lịch sử xét duyệt. Không thay thế nghiệm thu cảm biến |

Bộ test backend nằm ở `NguyenAnhDung.Attendance.Api.Tests`, dùng **WebApplicationFactory + SQLite in-memory** để gọi HTTP qua pipeline API, thay SMTP bằng bộ nhận thư trong test. Các ca đã đạt bao gồm đăng ký/xác thực/OTP và chống dùng lại mã, giới hạn nhập OTP sai, vô hiệu hóa phiên theo trạng thái tài khoản, RBAC, CRUD, QR tách khỏi access token, geofence, chấm trùng, quyền xem công, chấm ra và quyền sở hữu/duyệt đơn. Unit test kiểm tra thêm quy tắc mật khẩu, ca làm, khoảng cách và thời hạn QR. Test hồi quy schema dùng SQL Server provider để sinh DDL và kiểm tra khóa singleton `CompanySettings.Id` không có IDENTITY; test này **không mở kết nối SQL Server thật**.

SQLite không thay thế kiểm tra SQL Server rowversion, khóa giao dịch và các cuộc đua cập nhật/chấm công đồng thời trên SQL Server thật; email trong test không chứng minh SMTP đã gửi ra hộp thư. Kiểm thử Flutter cũng không chứng minh camera, vị trí hay cảm biến đã hoạt động trên điện thoại. Những bước thủ công bên dưới vẫn cần nhóm nghiệm thu trên môi trường thật.

Smoke process Kestrel dùng khóa JWT ngẫu nhiên, email Console chỉ ở Development, tắt khởi tạo database và BootstrapAdmin. Smoke này xác nhận host chạy và middleware xác thực/validation phản hồi đúng; không chạy luồng nghiệp vụ với SQL hoặc SMTP thật.

Sau khi cài Docker, đã kiểm tra thêm hệ thống local tại `localhost:5080` với SQL Server 2022 và SMTP Mailpit: khởi tạo dữ liệu, đăng nhập Admin bằng mật khẩu/OTP và đọc hồ sơ, cấu hình, Dashboard đều thành công. Địa chỉ SQL trong script chạy dùng `tcp:127.0.0.1,1433`; `localhost,1433` đã gây timeout 258 trên máy này. Đây là kiểm tra API với database và SMTP thật trong máy, chưa xác nhận toàn bộ thao tác qua giao diện hay phần cứng điện thoại.

## Đối chiếu yêu cầu chấm điểm

| Yêu cầu | Chức năng/hành vi cần chứng minh | Trạng thái nghiệm thu |
|---|---|---|
| Đăng ký email | Đăng ký Employee, nhận mã email, xác thực mới đăng nhập | Có luồng triển khai; cần kiểm chứng SMTP + điện thoại |
| Username + password + OTP | Bước mật khẩu tạo challenge; chỉ nhận token sau OTP đúng | Có luồng triển khai; cần kiểm chứng mã sai/hết hạn |
| Phân quyền | Admin vào quản trị, Manager vào giao diện quản lý, Employee vào Dashboard cá nhân | Cần kiểm chứng trên cả UI và API |
| CRUD (5,5 điểm theo đề) | Phòng ban, ca làm, nhân viên; đơn nghỉ phép/bổ sung công có CRUD và duyệt | Cần kiểm chứng tạo/đọc/sửa/xóa và ràng buộc |
| Nâng cao b | Vị trí hiện tại gửi khi chấm công, geofence phía server | Cần kiểm chứng GPS thật, ngoài vùng và từ chối quyền |
| Nâng cao d | Đo chuyển động từ gia tốc kế, hiển thị điểm đo, gửi cùng lượt công | Cần kiểm chứng cảm biến điện thoại thật |
| Nâng cao e | Camera quét QR ngắn hạn do Admin/Manager phát, server kiểm tra token | Cần kiểm chứng camera, QR hết hạn, QR không hợp lệ |
| Tính năng tự đề xuất | Phát hiện cùng lỗi từ 3 người trong 5 phút, quản lý xét duyệt giải trình theo nhóm | Xem [kịch bản sự cố](INCIDENTS.md); cần nghiệm thu theo môi trường được ghi nhận |
| Giao diện và cả nhóm chạy được | Luồng tiếng Việt, trạng thái tải/lỗi; mỗi thành viên tự cấu hình, chạy cùng source | Cần xác nhận trên từng máy thành viên |
| Tên theo cá nhân | Flutter folder NguyenAnhDung.Attendance.Mobile, API NguyenAnhDung.Attendance.Api, DB NguyenAnhDungAttendance | Đối chiếu tên khi nộp source và mở DB |

Chọn đúng **ba mục b, d, e**. Vân tay/NFC/QR/barcode đều thuộc e, không cộng thành nhiều mục. Gia tốc kế đo chuyển động là mục d; không dùng số ngẫu nhiên hoặc số nhập tay để giả lập cảm biến khi thuyết trình. Phân quyền API cần được thử độc lập, không chỉ ẩn nút trên giao diện. Đề tài này dùng Admin/Manager/Employee; không cần tạo vai trò khách hàng khi không có nghiệp vụ tương ứng.

## Chuẩn bị trước buổi demo

1. Làm theo README để chạy SQL, SMTP, API và Flutter. Kiểm tra `/health` từ thiết bị. Không đưa `.env`, mật khẩu, token hoặc OTP còn hiệu lực lên slide/ảnh công khai.
2. Chuẩn bị một tài khoản Admin, một Manager và ít nhất hai Employee; email của mỗi người phải đọc được. Bootstrap Admin là trường hợp khởi tạo riêng, các tài khoản mới phải xác thực email.
3. Chuẩn bị hai màn hình: Admin/Manager hiển thị QR trên một máy, điện thoại nhân viên dùng camera quét. Có thể dùng hai điện thoại; Mailpit chỉ mở trên máy chạy backend.
4. Admin đặt vị trí công ty ở địa điểm demo, bán kính/độ chính xác hợp lý và ca làm trong ngày. Gán ca, phòng ban cho tài khoản nhân viên. Ngày nghiệp vụ tính theo UTC+07:00.
5. Xin quyền camera/GPS khi app yêu cầu; bật GPS và mạng. Thử đo chuyển động trước để biết thiết bị có gia tốc kế. Ghi rõ những chức năng chưa thử được nếu dùng emulator.
6. Muốn demo gợi ý thiếu chấm ra: tạo lượt vào ngày trước rồi để mở qua ngày kế tiếp trong môi trường thử. Không sửa đồng hồ thiết bị để giả lập vì ngày chấm công do server quyết định. Nếu chưa có dữ liệu thật phù hợp, trình bày đây là tình huống chưa nghiệm thu.

## Trình tự demo khoảng 12–15 phút

### 1. Đăng ký, xác thực và OTP

1. Mở Đăng ký, nhập username mới, email, họ tên và mật khẩu đúng chính sách.
2. Mở email xác thực, nhập mã. Thử một mã sai trước, xác nhận app hiện lỗi và chưa cho đăng nhập.
3. Đăng nhập bằng username + mật khẩu. Chỉ nhập OTP từ email của challenge hiện tại; xác nhận chuyển vào Dashboard nhân viên.
4. Đăng xuất, đăng nhập Admin theo cùng quy trình OTP; xác nhận giao diện quản trị đúng vai trò.

Kết quả cần đạt: API không trả mã OTP/xác thực trong JSON; tài khoản chưa xác thực chưa nhận phiên đăng nhập; đăng xuất xóa phiên local.

### 2. CRUD và phân quyền

1. Admin tạo phòng ban thử, đọc danh sách, sửa mô tả và xóa phòng ban chưa có nhân viên.
2. Admin tạo ca thử, sửa thời gian/giờ cho phép đi trễ và xóa ca chưa được gán. Tạo lại một ca dùng cho demo.
3. Admin tạo một Employee, nhân viên xác thực email. Sửa họ tên/phòng ban/ca; sau đó vô hiệu hóa tài khoản thử không có lượt công cần giữ cho demo.
4. Nhân viên tạo đơn nghỉ phép Pending, sửa lý do, xóa đơn này rồi tạo đơn mới. Manager duyệt hoặc từ chối đơn của Employee; chủ đơn không tự duyệt được.
5. Dùng token Employee gọi endpoint quản trị bằng Postman/công cụ tương đương: phải nhận 403 khi tạo phòng ban, đổi công ty hoặc đổi vai trò. GET lịch sử/đơn chỉ thấy dữ liệu đúng quyền.

Ràng buộc cần thử: không xóa phòng ban/ca đang được gán; không vô hiệu hóa hoặc hạ quyền Admin cuối cùng; không sửa/xóa đơn đã duyệt. Xóa nhân viên ở đây là vô hiệu hóa để giữ lịch sử công.

### 3. Ba chức năng nâng cao b, d, e

1. **b — Vị trí:** nhân viên lấy GPS tại địa điểm demo. Hiển thị tọa độ/sai số hiện tại; API đối chiếu tọa độ công ty và bán kính.
2. **d — Chuyển động:** đo bằng gia tốc kế, di chuyển/để yên điện thoại và quan sát giá trị khác nhau. Giá trị được lưu kèm lượt công; không giới thiệu đây là bằng chứng chống chấm công hộ.
3. **e — QR:** Admin/Manager tạo QR mới. Nhân viên quét bằng camera rồi chấm vào; xác nhận Dashboard và lịch sử cập nhật.
4. Thử chấm vào lần thứ hai cùng ngày: API phải từ chối trùng. Thử QR cũ đã hết hạn với tài khoản chưa chấm hôm nay: phải từ chối.
5. Thử ngoài phạm vi bằng cách cấu hình vị trí công ty thử xa nơi đang đứng, rồi chấm bằng tài khoản khác: phải từ chối. Khôi phục cấu hình địa điểm demo sau đó.
6. Nhân viên chấm ra trong vùng. Lịch sử có giờ vào, giờ ra, thời gian làm; kiểm tra nhân viên khác không đọc được record này bằng tham số employeeId.

Vị trí chỉ chia sẻ theo thao tác chấm vào/chấm ra. QR phải được kiểm tra chữ ký và thời hạn trên server, không chỉ đọc được chuỗi là chấp nhận. QR phát chung trong thời hạn không phải QR cá nhân một lần; ràng buộc một lượt vào/người/ngày nằm ở server.

### 4. Tính năng nhóm tự đề xuất

1. Chuẩn bị 3 Employee đã xác thực/gán ca và chưa chấm vào. Dùng QR đã hết hạn để mỗi người gửi yêu cầu trong 5 phút; một người thử nhiều lần không đủ tạo sự cố.
2. Sau người thứ ba, mở **Sự cố chấm công**. Quản lý xem được nhóm người gặp cùng lỗi; nhân viên chỉ xem thông tin của mình.
3. Quản lý phát QR mới để nhân viên chấm lại. Mở sự cố, chọn những người cần xử lý, nhập lý do và duyệt/từ chối giải trình.
4. Đối chiếu trạng thái, người duyệt, lý do và thời điểm yêu cầu. Giờ vào/ra thực tế và cờ đi trễ không bị tự sửa. Thử gửi lại quyết định hoặc tự duyệt bản thân: phải bị từ chối.

Lợi ích: nhận ra trở ngại chung, giảm thao tác xử lý từng đơn và giữ lịch sử để đối chiếu. Xem [quy tắc, kịch bản chi tiết và phạm vi khảo sát](INCIDENTS.md). Đây là hướng khác biệt nhóm đề xuất; không khẳng định mọi app trên thị trường đều chưa có. Gợi ý đơn Correction cho ngày cũ thiếu chấm ra vẫn dùng được như tính năng bổ sung.

## Các ca nghiệm thu thủ công trên môi trường thật

Cột kết quả bên dưới dành cho thao tác với thiết bị, SMTP và SQL Server của nhóm; kết quả test tự động đã ghi riêng ở đầu tài liệu.

| Mã | Thao tác | Kết quả mong đợi | Kết quả thực tế |
|---|---|---|---|
| AUTH-01 | Đăng ký trùng username/email | Lỗi có thông báo; không tạo hai tài khoản | Chưa chạy |
| AUTH-02 | Login khi chưa xác thực email | Không cấp token | Chưa chạy |
| AUTH-03 | OTP sai/hết hạn/đã dùng lại | Không cấp token; giới hạn theo backend | Chưa chạy |
| AUTH-04 | Logout rồi mở lại app | Không vào màn hình bảo vệ bằng phiên cũ | Chưa chạy |
| ROLE-01 | Employee gọi POST /departments | HTTP 403 | Chưa chạy |
| ROLE-02 | Employee truy vấn attendance của người khác | Chỉ dữ liệu của mình/không lộ dữ liệu người khác | Chưa chạy |
| CRUD-01 | Tạo/sửa/xóa phòng ban, ca chưa dùng | Dữ liệu cập nhật sau tải lại | Chưa chạy |
| CRUD-02 | Xóa ca/phòng ban đã gán | Bị từ chối, dữ liệu không mất | Chưa chạy |
| CRUD-03 | Vô hiệu hóa Employee | Không đăng nhập mới được; giữ lịch sử | Chưa chạy |
| LEAVE-01 | Tạo/sửa/xóa đơn Pending | Đúng quyền sở hữu | Chưa chạy |
| LEAVE-02 | Tự duyệt, sửa đơn Approved | Bị từ chối | Chưa chạy |
| SENSOR-01 | Từ chối camera/GPS | App báo lỗi, có cách thử lại; không tự chấm công | Chưa chạy |
| SENSOR-02 | Đo gia tốc trên điện thoại | Số đo thực hiển thị và lưu cùng lượt công | Chưa chạy |
| ATT-01 | QR đúng + trong vùng + có ca | Chấm vào thành công | Chưa chạy |
| ATT-02 | QR hết hạn/sai + ngoài vùng/sai số lớn | Bị từ chối | Chưa chạy |
| ATT-03 | Chấm vào trùng trong ngày | Chỉ một record mỗi người/ngày | Chưa chạy |
| ATT-04 | Chấm ra khi chưa có lượt vào | Bị từ chối | Chưa chạy |
| EXTRA-01 | Ngày trước thiếu chấm ra | Có gợi ý; gửi/duyệt Correction không sửa giờ ngầm | Chưa chạy |
| INCIDENT-01 | Một người thử lỗi nhiều lần, rồi thêm người thứ hai/thứ ba | Chỉ tạo cảnh báo khi đủ 3 người trong 5 phút | Đạt với HTTP + SQL Server thật; ba tài khoản thử riêng |
| INCIDENT-02 | Đổi cấu hình văn phòng hoặc lỗi khác loại | Không gộp nhầm vào cùng sự cố | HTTP test tự động đạt; chưa demo đổi cấu hình trên thiết bị |
| INCIDENT-03 | Nhân viên xem chi tiết sự cố | Không đọc được danh tính/ghi chú người khác | Đạt với HTTP + SQL Server thật; truy cập nhóm không liên quan có test tự động |
| INCIDENT-04 | Quản lý duyệt lô hợp lệ, lô sai thành viên, duyệt lại | Lô hợp lệ có lịch sử; lô không hợp lệ bị từ chối toàn bộ | Đạt với HTTP + SQL Server thật; tự duyệt bị chặn trong test tự động |
| INCIDENT-05 | So sánh lịch sử công trước/sau xét duyệt | Giữ giờ vào/ra và IsLate | Đạt: response toàn bộ lịch sử công và đơn từ không đổi |

Thông tin lần nghiệm thu: ngày __________; người thử __________; thiết bị/Android __________; phiên bản Flutter/.NET __________; SMTP Mailpit/thật __________; kết quả build/analyze/test __________.

Trước khi nộp, mỗi thành viên chạy từ bản source sạch bằng hướng dẫn README và đánh dấu các bước đã hoàn thành. Cùng source trong nội bộ nhóm là để cộng tác; nhóm cần tuân thủ quy định giáo viên về phần code được phép dùng và không nộp source trùng nhóm khác.
