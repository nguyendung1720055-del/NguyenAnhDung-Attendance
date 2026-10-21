using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using NguyenAnhDung.Attendance.Api.Data;
using NguyenAnhDung.Attendance.Api.Models;
using NguyenAnhDung.Attendance.Api.Services;

namespace NguyenAnhDung.Attendance.Api.Controllers;

[ApiController, Route("api/auth"), EnableRateLimiting("auth")]
public class AuthController(AuthService auth, AttendanceDbContext db) : ControllerBase
{
    [HttpPost("register")]
    public async Task<object> Register(RegisterInput input, CancellationToken ct)
    {
        await auth.RegisterAsync(input, ct);
        return new { Message = "Đăng ký thành công. Hãy kiểm tra email để lấy mã xác thực." };
    }
    [HttpPost("verify-email")]
    public async Task<object> VerifyEmail(VerifyEmailInput input, CancellationToken ct)
    {
        await auth.VerifyEmailAsync(input, ct);
        return new { Message = "Email đã được xác thực. Bạn có thể đăng nhập." };
    }
    [HttpPost("resend-verification")]
    public async Task<object> Resend(EmailInput input, CancellationToken ct)
    {
        var normalized = Rules.Normalize(input.Email);
        var user = await db.Employees.SingleOrDefaultAsync(u => u.NormalizedEmail == normalized && u.IsActive && !u.EmailVerified, ct);
        if (user is not null)
        {
            try { await auth.IssueAsync(user, "VerifyEmail", ct); }
            catch (ApiException ex) when (ex.Status == 429) { /* Keep account existence private. */ }
        }
        return new { Message = "Nếu email cần xác thực, mã mới sẽ được gửi. Vui lòng kiểm tra hộp thư." };
    }
    [HttpPost("login")]
    public Task<object> Login(LoginInput input, CancellationToken ct) => auth.LoginAsync(input, ct);
    [HttpPost("verify-otp")]
    public Task<object> VerifyOtp(VerifyOtpInput input, CancellationToken ct) => auth.VerifyOtpAsync(input, ct);
    [Authorize, HttpGet("me")]
    public async Task<object> Me(CancellationToken ct)
    {
        var id = Guid.Parse(User.FindFirstValue("sub")!);
        var user = await db.Employees.AsNoTracking().SingleAsync(e => e.Id == id, ct);
        return UserView.From(user);
    }
}
