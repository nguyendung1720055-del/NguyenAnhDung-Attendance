using System.Globalization;
using System.Net.Mail;
using System.Net;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using NguyenAnhDung.Attendance.Api.Models;

namespace NguyenAnhDung.Attendance.Api.Services;

public class ApiException(int status, string message) : Exception(message)
{
    public int Status { get; } = status;
    public static ApiException Bad(string message) => new(400, message);
    public static ApiException Missing(string message = "Không tìm thấy dữ liệu.") => new(404, message);
    public static ApiException Conflict(string message) => new(409, message);
    public static ApiException Forbidden(string message = "Bạn không có quyền thực hiện thao tác này.") => new(403, message);
    public static ApiException Unauthorized(string message = "Thông tin xác thực không hợp lệ hoặc đã hết hạn.") => new(401, message);
}

public class ErrorMiddleware(RequestDelegate next, ILogger<ErrorMiddleware> logger)
{
    public async Task InvokeAsync(HttpContext context)
    {
        try { await next(context); }
        catch (Exception ex) when (!context.Response.HasStarted)
        {
            var (status, message) = ex switch {
                ApiException a => (a.Status, a.Message),
                DbUpdateConcurrencyException => (409, "Dữ liệu vừa thay đổi. Vui lòng tải lại và thử lại."),
                DbUpdateException { InnerException: SqlException { Number: 2601 or 2627 } } => (409, "Dữ liệu đã tồn tại hoặc bạn đã chấm công hôm nay."),
                DbUpdateException { InnerException: SqlException { Number: 547 } } => (409, "Dữ liệu đang được sử dụng hoặc tham chiếu không hợp lệ."),
                DbUpdateException { InnerException: SqlException { Number: 1205 } } => (409, "Có thao tác quản trị đồng thời. Vui lòng tải lại và thử lại."),
                SqlException { Number: 1205 } => (409, "Có thao tác quản trị đồng thời. Vui lòng tải lại và thử lại."),
                BadHttpRequestException => (400, "Yêu cầu không hợp lệ."),
                _ => (500, "Hệ thống gặp sự cố. Vui lòng thử lại sau.")
            };
            if (status >= 500) logger.LogError(ex, "Request failed: {Path}", context.Request.Path);
            context.Response.StatusCode = status;
            await context.Response.WriteAsJsonAsync(new { message });
        }
    }
}

public static class Rules
{
    public static readonly TimeSpan BusinessOffset = TimeSpan.FromHours(7);
    public static DateOnly Today => DateOnly.FromDateTime(DateTime.UtcNow.Add(BusinessOffset));
    public static string Normalize(string value) => value.Trim().ToUpperInvariant();
    public static void Password(string password)
    {
        if (password.Length is < 10 or > 128 || !password.Any(char.IsUpper) || !password.Any(char.IsLower) || !password.Any(char.IsDigit))
            throw ApiException.Bad("Mật khẩu cần 10–128 ký tự, gồm chữ hoa, chữ thường và chữ số.");
    }
    public static void Name(string name, int min = 2)
    {
        if (name.Trim().Length < min) throw ApiException.Bad("Tên không được để trống hoặc quá ngắn.");
    }
    public static (TimeOnly Start, TimeOnly End) ShiftTimes(ShiftInput input)
    {
        if (!TimeOnly.TryParseExact(input.StartTime, "HH:mm", CultureInfo.InvariantCulture, DateTimeStyles.None, out var start)
            || !TimeOnly.TryParseExact(input.EndTime, "HH:mm", CultureInfo.InvariantCulture, DateTimeStyles.None, out var end)
            || end <= start)
            throw ApiException.Bad("Giờ ca làm phải có dạng HH:mm; giờ kết thúc sau giờ bắt đầu, trong cùng ngày.");
        return (start, end);
    }
    public static bool CoordinatesValid(double latitude, double longitude) => double.IsFinite(latitude) && double.IsFinite(longitude) && latitude is >= -90 and <= 90 && longitude is >= -180 and <= 180;
    public static double DistanceMeters(double latitude, double longitude, double officeLat, double officeLon)
    {
        static double Rad(double x) => x * Math.PI / 180;
        var dLat = Rad(officeLat - latitude); var dLon = Rad(officeLon - longitude);
        var a = Math.Pow(Math.Sin(dLat / 2), 2) + Math.Cos(Rad(latitude)) * Math.Cos(Rad(officeLat)) * Math.Pow(Math.Sin(dLon / 2), 2);
        return 6371000 * 2 * Math.Asin(Math.Sqrt(Math.Clamp(a, 0, 1)));
    }
    public static void AttendanceMeasurement(double lat, double lon, double accuracy, double motion)
    {
        if (!CoordinatesValid(lat, lon) || !double.IsFinite(accuracy) || accuracy <= 0 || !double.IsFinite(motion) || motion is < 0 or > 100000)
            throw ApiException.Bad("Tọa độ, độ chính xác GPS hoặc dữ liệu chuyển động không hợp lệ.");
    }
    public static void Location(CompanySettings settings, double lat, double lon, double accuracy, double motion)
    {
        AttendanceMeasurement(lat, lon, accuracy, motion);
        if (accuracy > settings.MaxAccuracyMeters) throw ApiException.Bad("GPS chưa đủ chính xác. Hãy ra nơi thoáng và đo lại.");
        if (DistanceMeters(lat, lon, settings.Latitude, settings.Longitude) > settings.RadiusMeters)
            throw ApiException.Bad("Bạn đang ở ngoài phạm vi chấm công của công ty.");
    }
    public static void Leave(LeaveInput input)
    {
        if (input.Type is not ("Annual" or "Sick" or "Unpaid" or "Correction")) throw ApiException.Bad("Loại đơn không hợp lệ.");
        if (input.StartDate == default || input.EndDate == default || input.EndDate < input.StartDate || input.EndDate.DayNumber - input.StartDate.DayNumber > 365)
            throw ApiException.Bad("Khoảng ngày của đơn không hợp lệ (tối đa 366 ngày).");
        if (input.Reason.Trim().Length < 5) throw ApiException.Bad("Vui lòng nhập lý do ít nhất 5 ký tự.");
        if (input.Type == "Correction" && (input.StartDate != input.EndDate || input.StartDate >= Today))
            throw ApiException.Bad("Đơn bổ sung công dành cho một ngày đã qua.");
    }
    public static void Settings(SettingsInput s)
    {
        Name(s.OfficeName);
        if (!CoordinatesValid(s.Latitude, s.Longitude) || !double.IsFinite(s.RadiusMeters) || s.RadiusMeters is < 20 or > 5000
            || !double.IsFinite(s.MaxAccuracyMeters) || s.MaxAccuracyMeters is < 5 or > 500 || s.QrLifetimeSeconds is < 15 or > 300)
            throw ApiException.Bad("Cài đặt không hợp lệ. Bán kính 20–5000 m, độ chính xác 5–500 m, QR 15–300 giây.");
    }
}

public sealed class JwtOptions
{
    public string Key { get; set; } = "";
    public string Issuer { get; set; } = "NguyenAnhDung.Attendance.Api";
    public string Audience { get; set; } = "NguyenAnhDung.Attendance.Mobile";
    public int LifetimeMinutes { get; set; } = 60;
}

public sealed class EmailOptions
{
    public string DeliveryMethod { get; set; } = "Smtp";
    public string Host { get; set; } = "";
    public int Port { get; set; } = 587;
    public bool UseSsl { get; set; } = true;
    public string Username { get; set; } = "";
    public string Password { get; set; } = "";
    public string FromAddress { get; set; } = "";
    public string FromName { get; set; } = "Nguyên Anh Dũng - Chấm công";
}

public interface IEmailSender
{
    Task SendCodeAsync(string email, string code, string purpose, CancellationToken ct);
}

public sealed class EmailSender(EmailOptions options, IWebHostEnvironment environment, ILogger<EmailSender> logger) : IEmailSender
{
    public async Task SendCodeAsync(string email, string code, string purpose, CancellationToken ct)
    {
        var title = purpose == "VerifyEmail" ? "Xác thực email" : "OTP đăng nhập";
        if (options.DeliveryMethod == "Console" && environment.IsDevelopment())
        {
            logger.LogWarning("[DEVELOPMENT EMAIL ONLY] To={Email}; Subject={Title}; Code={Code}; expires in 10 minutes. Never enable in production.", email, title, code);
            return;
        }
        using var client = new SmtpClient(options.Host, options.Port) { EnableSsl = options.UseSsl, Timeout = 15000 };
        if (!string.IsNullOrWhiteSpace(options.Username)) client.Credentials = new NetworkCredential(options.Username, options.Password);
        using var message = new MailMessage(new MailAddress(options.FromAddress, options.FromName), new MailAddress(email))
        {
            Subject = $"{title} - Chấm công Hữu Duyên",
            Body = $"Mã {title.ToLowerInvariant()} của bạn: {code}\nMã có hiệu lực 10 phút, tối đa 5 lần nhập. Không chia sẻ mã với người khác.\nNếu bạn không yêu cầu, hãy bỏ qua email này.",
            IsBodyHtml = false
        };
        try { await client.SendMailAsync(message, ct); }
        catch (Exception ex) when (ex is SmtpException or InvalidOperationException)
        {
            logger.LogError(ex, "SMTP delivery failed.");
            throw new ApiException(503, "Chưa gửi được email. Vui lòng kiểm tra cấu hình SMTP và thử gửi lại mã.");
        }
    }
}
