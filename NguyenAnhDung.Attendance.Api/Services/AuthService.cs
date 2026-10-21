using System.Security.Cryptography;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using NguyenAnhDung.Attendance.Api.Data;
using NguyenAnhDung.Attendance.Api.Models;

namespace NguyenAnhDung.Attendance.Api.Services;

public class AuthService(AttendanceDbContext db, IPasswordHasher<Employee> hasher, TokenService tokens, IEmailSender email)
{
    public async Task<Employee> RegisterAsync(RegisterInput input, CancellationToken ct, string role = Roles.Employee, Guid? departmentId = null, Guid? shiftId = null)
    {
        Rules.Password(input.Password); Rules.Name(input.FullName);
        var normalizedUsername = Rules.Normalize(input.Username); var normalizedEmail = Rules.Normalize(input.Email);
        if (await db.Employees.AnyAsync(e => e.NormalizedUsername == normalizedUsername || e.NormalizedEmail == normalizedEmail, ct))
            throw ApiException.Conflict("Tên đăng nhập hoặc email đã được sử dụng.");
        var user = new Employee { Username = input.Username.Trim(), NormalizedUsername = normalizedUsername, Email = input.Email.Trim(), NormalizedEmail = normalizedEmail, FullName = input.FullName.Trim(), Role = role, DepartmentId = departmentId, ShiftId = shiftId };
        user.PasswordHash = hasher.HashPassword(user, input.Password);
        db.Employees.Add(user);
        await db.SaveChangesAsync(ct);
        await IssueAsync(user, "VerifyEmail", ct);
        return user;
    }

    public async Task<EmailChallenge> IssueAsync(Employee user, string purpose, CancellationToken ct)
    {
        var now = DateTime.UtcNow;
        var old = await db.EmailChallenges.Where(c => c.EmployeeId == user.Id && c.Purpose == purpose && !c.Consumed).ToListAsync(ct);
        if (old.Any(c => c.CreatedAtUtc > now.AddSeconds(-45) && c.ExpiresAtUtc > now && c.Attempts < 5))
            throw new ApiException(429, "Vui lòng đợi 45 giây trước khi yêu cầu mã mới.");
        foreach (var previous in old) previous.Consumed = true;
        var code = RandomNumberGenerator.GetInt32(0, 1000000).ToString("D6");
        var challenge = new EmailChallenge { EmployeeId = user.Id, Purpose = purpose, ExpiresAtUtc = now.AddMinutes(10), CreatedAtUtc = now };
        challenge.CodeHash = tokens.HashCode(challenge.Id, purpose, code);
        db.EmailChallenges.Add(challenge);
        await db.SaveChangesAsync(ct);
        try { await email.SendCodeAsync(user.Email, code, purpose, ct); }
        catch
        {
            challenge.Consumed = true;
            await db.SaveChangesAsync(CancellationToken.None);
            throw;
        }
        return challenge;
    }

    public async Task VerifyEmailAsync(VerifyEmailInput input, CancellationToken ct)
    {
        var normalized = Rules.Normalize(input.Email);
        var user = await db.Employees.SingleOrDefaultAsync(u => u.NormalizedEmail == normalized && u.IsActive, ct);
        if (user is null) throw ApiException.Bad("Email hoặc mã xác thực không hợp lệ.");
        var challenge = await db.EmailChallenges.Where(c => c.EmployeeId == user.Id && c.Purpose == "VerifyEmail" && !c.Consumed).OrderByDescending(c => c.CreatedAtUtc).FirstOrDefaultAsync(ct);
        await ConsumeAsync(challenge, input.Code, ct);
        user.EmailVerified = true;
        await db.SaveChangesAsync(ct);
    }

    public async Task<object> LoginAsync(LoginInput input, CancellationToken ct)
    {
        var normalized = Rules.Normalize(input.Identifier);
        var user = await db.Employees.SingleOrDefaultAsync(e => e.NormalizedUsername == normalized || e.NormalizedEmail == normalized, ct);
        var invalid = "Tên đăng nhập, mật khẩu không đúng hoặc tài khoản tạm bị khóa.";
        if (user is null || !user.IsActive || user.LockedUntilUtc > DateTime.UtcNow) throw ApiException.Unauthorized(invalid);
        var result = hasher.VerifyHashedPassword(user, user.PasswordHash, input.Password);
        if (result == PasswordVerificationResult.Failed)
        {
            user.FailedLoginAttempts++;
            if (user.FailedLoginAttempts >= 5) { user.LockedUntilUtc = DateTime.UtcNow.AddMinutes(15); user.FailedLoginAttempts = 0; }
            await db.SaveChangesAsync(ct);
            throw ApiException.Unauthorized(invalid);
        }
        if (!user.EmailVerified) throw ApiException.Forbidden("Bạn cần xác thực email trước khi đăng nhập.");
        user.FailedLoginAttempts = 0; user.LockedUntilUtc = null;
        if (result == PasswordVerificationResult.SuccessRehashNeeded) user.PasswordHash = hasher.HashPassword(user, input.Password);
        var challenge = await IssueAsync(user, "LoginOtp", ct);
        return new { ChallengeId = challenge.Id, MaskedEmail = MaskEmail(user.Email), challenge.ExpiresAtUtc };
    }

    public async Task<object> VerifyOtpAsync(VerifyOtpInput input, CancellationToken ct)
    {
        var challenge = await db.EmailChallenges.Include(c => c.Employee).SingleOrDefaultAsync(c => c.Id == input.ChallengeId && c.Purpose == "LoginOtp", ct);
        if (challenge is null || !challenge.Employee.IsActive || !challenge.Employee.EmailVerified) throw ApiException.Unauthorized();
        await ConsumeAsync(challenge, input.Code, ct);
        // Persist the single-use change BEFORE returning an access token. Rowversion rejects concurrent replay.
        await db.SaveChangesAsync(ct);
        var (token, expiry) = tokens.Access(challenge.Employee);
        return new { AccessToken = token, ExpiresAtUtc = expiry, User = UserView.From(challenge.Employee) };
    }

    private async Task ConsumeAsync(EmailChallenge? challenge, string code, CancellationToken ct)
    {
        if (challenge is null || challenge.Consumed || challenge.ExpiresAtUtc <= DateTime.UtcNow || challenge.Attempts >= 5)
            throw ApiException.Bad("Mã không hợp lệ, đã hết hạn hoặc đã dùng. Hãy yêu cầu mã mới.");
        challenge.Attempts++;
        if (!tokens.CodeMatches(challenge, code))
        {
            if (challenge.Attempts >= 5) challenge.Consumed = true;
            await db.SaveChangesAsync(ct);
            throw ApiException.Bad("Mã không đúng. Mỗi mã được nhập tối đa 5 lần.");
        }
        challenge.Consumed = true;
    }

    private static string MaskEmail(string value)
    {
        var at = value.IndexOf('@');
        return at <= 1 ? "*" + value[at..] : value[..1] + "***" + value[at..];
    }
}
