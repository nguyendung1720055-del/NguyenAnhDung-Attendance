using System.ComponentModel.DataAnnotations;

namespace NguyenAnhDung.Attendance.Api.Models;

public record RegisterInput(
    [Required, RegularExpression(@"^[A-Za-z0-9_.]{3,40}$")] string Username,
    [Required, EmailAddress, MaxLength(254)] string Email,
    [Required, StringLength(160, MinimumLength = 2)] string FullName,
    [Required, StringLength(128, MinimumLength = 10)] string Password);
public record EmailInput([Required, EmailAddress, MaxLength(254)] string Email);
public record VerifyEmailInput([Required, EmailAddress, MaxLength(254)] string Email, [Required, RegularExpression(@"^\d{6}$")] string Code);
public record LoginInput([Required, MaxLength(254)] string Identifier, [Required, MaxLength(128)] string Password);
public record VerifyOtpInput(Guid ChallengeId, [Required, RegularExpression(@"^\d{6}$")] string Code);
public record DepartmentInput([Required, StringLength(120, MinimumLength = 2)] string Name, [MaxLength(600)] string? Description);
public record ShiftInput([Required, StringLength(120, MinimumLength = 2)] string Name, [Required] string StartTime, [Required] string EndTime, [Range(0, 120)] int GraceMinutes);
public record CreateEmployeeInput(
    [Required, RegularExpression(@"^[A-Za-z0-9_.]{3,40}$")] string Username,
    [Required, EmailAddress, MaxLength(254)] string Email,
    [Required, StringLength(160, MinimumLength = 2)] string FullName,
    [Required, StringLength(128, MinimumLength = 10)] string Password,
    [Required] string Role, Guid? DepartmentId, Guid? ShiftId);
public record UpdateEmployeeInput([Required, StringLength(160, MinimumLength = 2)] string FullName, [Required] string Role, Guid? DepartmentId, Guid? ShiftId, bool IsActive);
public record CheckInInput([Required, MaxLength(4096)] string QrToken, double Latitude, double Longitude, double AccuracyMeters, double MotionScore);
public record CheckOutInput(double Latitude, double Longitude, double AccuracyMeters, double MotionScore);
public record LeaveInput([Required] string Type, DateOnly StartDate, DateOnly EndDate, [Required, StringLength(2000, MinimumLength = 5)] string Reason);
public record ReviewInput([Required] string Status, [MaxLength(1000)] string? ReviewNote);
public record SettingsInput([Required, StringLength(160, MinimumLength = 2)] string OfficeName, double Latitude, double Longitude, double RadiusMeters, double MaxAccuracyMeters, int QrLifetimeSeconds);

public record UserView(Guid Id, string Username, string Email, string FullName, string Role, Guid? DepartmentId, Guid? ShiftId, bool IsActive, bool EmailVerified)
{
    public static UserView From(Employee e) => new(e.Id, e.Username, e.Email, e.FullName, e.Role, e.DepartmentId, e.ShiftId, e.IsActive, e.EmailVerified);
}

public static class Views
{
    public static object Department(Department d) => new { d.Id, d.Name, d.Description };
    public static object Shift(Shift s) => new { s.Id, s.Name, StartTime = s.StartTime.ToString("HH:mm"), EndTime = s.EndTime.ToString("HH:mm"), s.GraceMinutes };
    public static object Attendance(Attendance a) => new {
        a.Id, a.EmployeeId, EmployeeName = a.Employee.FullName, DepartmentName = a.Employee.Department?.Name,
        a.WorkDate, a.CheckInAtUtc, a.CheckOutAtUtc, a.IsLate, a.Latitude, a.Longitude, a.AccuracyMeters, a.MotionScore,
        WorkedMinutes = a.CheckOutAtUtc.HasValue ? (int)Math.Max(0, (a.CheckOutAtUtc.Value - a.CheckInAtUtc).TotalMinutes) : 0
    };
    public static object Leave(LeaveRequest r) => new {
        r.Id, r.EmployeeId, EmployeeName = r.Employee.FullName, r.Type, r.StartDate, r.EndDate, r.Reason, r.Status,
        r.ReviewNote, ReviewerName = r.Reviewer?.FullName, r.CreatedAtUtc
    };
    public static object Settings(CompanySettings s) => new { s.OfficeName, s.Latitude, s.Longitude, s.RadiusMeters, s.MaxAccuracyMeters, s.QrLifetimeSeconds };
}
