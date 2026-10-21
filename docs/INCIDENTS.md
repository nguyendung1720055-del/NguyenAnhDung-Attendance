# Phát hiện và xử lý sự cố chấm công tập thể

Tính năng nhóm **Hữu Duyên** tự đề xuất cho app chấm công. Mục tiêu là giúp quản lý nhận ra nhiều nhân viên gặp cùng trở ngại và xử lý giải trình trong cùng một màn hình.

## Tình huống sử dụng

Gần giờ vào ca, nhiều nhân viên quét một mã QR đã hết hạn. Mỗi người vẫn nhận thông báo lỗi và cần quét lại. Khi máy chủ ghi nhận cùng loại lỗi từ ít nhất **3 nhân viên khác nhau trong 5 phút**, app tạo cảnh báo nghi sự cố chung. Quản lý có thể xem từng người, thời điểm yêu cầu đầu/cuối và số lần thử, rồi chọn những người phù hợp để duyệt hoặc từ chối giải trình kèm lý do.

## Quy tắc

- Lấy thời điểm máy chủ nhận yêu cầu; không dùng giờ điện thoại để quyết định cửa sổ 5 phút.
- Đếm người khác nhau, không đếm một người bấm lặp nhiều lần thành nhiều người.
- Nhóm theo cùng loại lỗi và cùng cấu hình văn phòng tại thời điểm xảy ra, tránh gộp lỗi từ các quy định khác nhau.
- Các lỗi được xem xét: QR sai/hết hạn, GPS chưa đủ chính xác, ở ngoài vùng văn phòng. Yêu cầu vẫn bị từ chối theo quy định chấm công ban đầu.
- Chỉ ghi nhận yêu cầu đủ điều kiện đã tới API. App mất mạng, chưa cấp quyền GPS/camera, dữ liệu sai định dạng, chưa được gán ca hoặc đã chấm trùng không tự tạo bằng chứng sự cố chung.
- Không lưu nội dung QR vào nhật ký sự cố. Nhân viên chỉ xem phần giải trình của chính mình; quản lý xem theo quyền.
- Quản lý chọn người đang chờ xét duyệt, nhập lý do **5–1000 ký tự**, duyệt hoặc từ chối. Không tự duyệt bản thân, không xét lại người đã có quyết định. Lô có phần tử không hợp lệ bị từ chối toàn bộ.
- **Duyệt giải trình chỉ xác nhận quyết định xử lý sự cố.** Tính năng không tự tạo giờ công, không sửa giờ vào/ra, không đổi `IsLate` hay tự miễn phạt đi trễ. Việc áp dụng vào chính sách nhân sự vẫn cần bước nghiệp vụ riêng.

## Kịch bản demo

1. Chuẩn bị Admin/Manager và **3 Employee khác nhau**, đã xác thực email và được gán ca. Cả ba chưa chấm vào trong ngày.
2. Quản lý tạo QR; nhân viên quét bằng camera. Lấy GPS và đo chuyển động trước khi xác nhận chấm công.
3. Chờ QR hết hạn rồi lần lượt gửi yêu cầu từ ba nhân viên trong vòng 5 phút. Sau hai người, chưa có sự cố tập thể. Một người thử lại nhiều lần vẫn không thay thế người thứ ba.
4. Sau người thứ ba, mở **Sự cố chấm công**. Quản lý xem được cảnh báo, loại lỗi và danh sách ba người; nhân viên chỉ thấy thông tin của mình.
5. Phát QR mới để nhân viên chấm lại đúng quy trình. Các lượt công giữ giờ thực tế của lần chấm thành công.
6. Quản lý mở chi tiết sự cố, chọn các nhân viên cần xử lý, nhập lý do và duyệt/từ chối. Kiểm tra trạng thái, người xét duyệt và ghi chú được lưu; lịch sử công không bị đổi giờ ngầm.
7. Thử dùng tài khoản Employee gọi API xét duyệt, tự xét duyệt bằng tài khoản quản lý, hoặc gửi lại quyết định đã xử lý: API phải từ chối.

Nếu chỉ kiểm tra HTTP bằng dữ liệu tọa độ gửi tay, ghi rõ đó là kiểm thử API; không thay thế demo camera, GPS và gia tốc kế thật cho ba mục b/d/e.

## Cài đặt và dữ liệu

Tính năng bổ sung ba bảng cho nhật ký lỗi, sự cố và người liên quan. Khi `Database__Initialize=true`, API áp dụng [Upgrade-AttendanceIncidents.sql](../NguyenAnhDung.Attendance.Api/database/Upgrade-AttendanceIncidents.sql), được nhúng trong bản build, sau bước tạo database lần đầu. Script chỉ tạo bảng/index còn thiếu trong giao dịch; có thể chạy lại và không xóa hoặc tạo lại dữ liệu nhân viên/chấm công. Nếu tắt khởi tạo tự động, quản trị viên cần chạy script trên đúng database trước khi bật tính năng. Sao lưu database trước khi cập nhật. Schema SQL Server đầy đủ dành cho database mới vẫn nằm trong thư mục `NguyenAnhDung.Attendance.Api/database`.

## Kết quả đã kiểm chứng — 21/10/2026

- Backend **25/25 tests đạt**, Flutter **12/12 tests đạt**, analyzer không có lỗi; build APK mới thành công.
- SQL Server thật: sao lưu kèm kiểm tra checksum trước cập nhật; khởi động API bổ sung bảng, chạy lại script nâng cấp thành công. Dữ liệu cũ vẫn có 4 tài khoản, 1 lượt công và 1 đơn trước khi thêm dữ liệu thử.
- Tạo 3 tài khoản thử riêng bằng API, xác thực email và đăng nhập OTP qua SMTP Mailpit. Một người thử lỗi nhiều lần hoặc hai người không tạo cảnh báo; người thứ ba tạo đúng một sự cố.
- Kiểm tra nhân viên chỉ đọc chi tiết của mình, không có quyền xét duyệt; lô có người không thuộc sự cố bị từ chối và giữ cả ba người Pending; quản lý duyệt hai người, từ chối một người, sự cố chuyển Resolved. Gửi lại lô đã duyệt bị từ chối.
- So sánh toàn bộ response lịch sử công và đơn từ trước/sau: không thay đổi. Ba tài khoản thử đã được vô hiệu hóa sau kiểm thử; giữ sự cố demo đã xử lý để xem lịch sử.
- APK đã cài cập nhật trên `Small_Phone`; mở được danh sách và chi tiết sự cố thật từ API, quan sát được trạng thái, ba người ảnh hưởng và lịch sử xét duyệt.

Luồng tạo lỗi trong lần kiểm chứng tích hợp dùng HTTP và dữ liệu vị trí gửi tay, không phải nghiệm thu camera/GPS/gia tốc kế. Các phần cứng đó vẫn cần chạy theo kịch bản demo ở trên.

## Cách trình bày tính mới

Điểm khác biệt nhóm đề xuất là chuỗi **phát hiện lỗi tương quan giữa nhiều nhân viên → cảnh báo chung → chọn và xét duyệt giải trình theo nhóm**, có thời điểm yêu cầu trên máy chủ để đối chiếu.

GPS, QR, nhắc quên chấm công và chế độ offline đã được các sản phẩm như [Jibble](https://www.jibble.io/features) và [Tanca](https://tanca.io/feature/attendance) công bố. Đây là phạm vi đối chiếu tài liệu công khai, không phải bằng chứng rằng mọi sản phẩm khác đều chưa có quy trình tương tự. Khi thuyết trình, nêu đúng các app đã khảo sát và phần khác biệt của bản nhóm thực hiện; không khẳng định độc quyền hoặc đảm bảo điểm số.
