using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NguyenAnhDung.Attendance.Api.Data;
using NguyenAnhDung.Attendance.Api.Models;
using NguyenAnhDung.Attendance.Api.Services;
using AttendanceRecord = NguyenAnhDung.Attendance.Api.Models.Attendance;

namespace NguyenAnhDung.Attendance.Api.Controllers;

[ApiController, Authorize, Route("api/attendance")]
public class AttendanceController(AttendanceDbContext db, TokenService tokens, AttendanceIncidentService incidents, ILogger<AttendanceController> logger) : ControllerBase
{
    private Guid CurrentId => Guid.Parse(User.FindFirstValue("sub")!);
    private bool IsSupervisor => User.IsInRole(Roles.Admin) || User.IsInRole(Roles.Manager);

    [HttpGet]
    public async Task<object> List([FromQuery] DateOnly? from, [FromQuery] DateOnly? to, [FromQuery] Guid? employeeId, CancellationToken ct)
    {
        if (from.HasValue && to.HasValue && from > to) throw ApiException.Bad("Ngày bắt đầu phải trước hoặc bằng ngày kết thúc.");
        if (!IsSupervisor && employeeId.HasValue && employeeId != CurrentId) throw ApiException.Forbidden();
        var query = db.Attendances.AsNoTracking().Include(a => a.Employee).ThenInclude(e => e.Department).AsQueryable();
        if (!IsSupervisor) query = query.Where(a => a.EmployeeId == CurrentId);
        else if (employeeId.HasValue) query = query.Where(a => a.EmployeeId == employeeId);
        if (from.HasValue) query = query.Where(a => a.WorkDate >= from.Value);
        if (to.HasValue) query = query.Where(a => a.WorkDate <= to.Value);
        return (await query.OrderByDescending(a => a.WorkDate).ThenBy(a => a.Employee.FullName).ToListAsync(ct)).Select(Views.Attendance);
    }

    [HttpGet("summary")]
    public async Task<object> Summary(CancellationToken ct)
    {
        var today = Rules.Today;
        var monthStart = new DateOnly(today.Year, today.Month, 1);
        var nextMonth = monthStart.AddMonths(1);
        var rows = await db.Attendances.AsNoTracking().Where(a => a.EmployeeId == CurrentId && a.WorkDate >= monthStart && a.WorkDate < nextMonth).ToListAsync(ct);
        var current = rows.SingleOrDefault(a => a.WorkDate == today);
        var missing = await db.Attendances.CountAsync(a => a.EmployeeId == CurrentId && a.WorkDate < today && a.CheckOutAtUtc == null, ct);
        var totalMinutes = rows.Where(a => a.CheckOutAtUtc.HasValue).Sum(a => Math.Max(0, (a.CheckOutAtUtc!.Value - a.CheckInAtUtc).TotalMinutes));
        return new {
            TodayStatus = current is null ? "NotCheckedIn" : current.CheckOutAtUtc.HasValue ? "Completed" : "Working",
            CheckedInAtUtc = current?.CheckInAtUtc, CheckedOutAtUtc = current?.CheckOutAtUtc,
            TotalDaysThisMonth = rows.Count, LateDaysThisMonth = rows.Count(a => a.IsLate),
            TotalHoursThisMonth = Math.Round(totalMinutes / 60, 2), MissingCheckoutCount = missing
        };
    }

    [HttpPost("qr"), Authorize(Roles = Roles.Supervisors)]
    public async Task<object> CreateQr(CancellationToken ct)
    {
        var settings = await db.CompanySettings.AsNoTracking().SingleAsync(s => s.Id == 1, ct);
        var (token, expiry) = tokens.Qr(settings.QrLifetimeSeconds, CurrentId);
        return new { Token = token, ExpiresAtUtc = expiry };
    }

    [HttpPost("check-in")]
    public async Task<object> CheckIn(CheckInInput input, CancellationToken ct)
    {
        Rules.AttendanceMeasurement(input.Latitude, input.Longitude, input.AccuracyMeters, input.MotionScore);
        var settings = await db.CompanySettings.AsNoTracking().SingleAsync(s => s.Id == 1, ct);
        var employee = await db.Employees.Include(e => e.Shift).Include(e => e.Department).SingleAsync(e => e.Id == CurrentId, ct);
        if (employee.Shift is null) throw ApiException.Bad("Bạn chưa được gán ca làm. Hãy liên hệ Admin.");
        var now = DateTime.UtcNow;
        var workDate = DateOnly.FromDateTime(now.Add(Rules.BusinessOffset));
        if (await db.Attendances.AnyAsync(a => a.EmployeeId == employee.Id && a.WorkDate == workDate, ct)) throw ApiException.Conflict("Bạn đã chấm công vào hôm nay.");
        try { tokens.ValidateQr(input.QrToken); }
        catch (ApiException) { await RecordFailure(settings, AttendanceIncidentService.QrInvalidOrExpired, "CheckIn", ct); throw; }
        await ValidateLocation(settings, input.Latitude, input.Longitude, input.AccuracyMeters, input.MotionScore, "CheckIn", ct);
        var latestOnTime = new DateTimeOffset(workDate.ToDateTime(employee.Shift.StartTime), Rules.BusinessOffset).UtcDateTime.AddMinutes(employee.Shift.GraceMinutes);
        var attendance = new AttendanceRecord {
            EmployeeId = employee.Id, Employee = employee, WorkDate = workDate, CheckInAtUtc = now, IsLate = now > latestOnTime,
            Latitude = input.Latitude, Longitude = input.Longitude, AccuracyMeters = input.AccuracyMeters, MotionScore = input.MotionScore
        };
        db.Attendances.Add(attendance);
        // Unique (EmployeeId, WorkDate) also rejects concurrent duplicate submissions.
        await db.SaveChangesAsync(ct);
        return Views.Attendance(attendance);
    }

    [HttpPost("check-out")]
    public async Task<object> CheckOut(CheckOutInput input, CancellationToken ct)
    {
        var settings = await db.CompanySettings.AsNoTracking().SingleAsync(s => s.Id == 1, ct);
        Rules.AttendanceMeasurement(input.Latitude, input.Longitude, input.AccuracyMeters, input.MotionScore);
        var today = Rules.Today;
        var record = await db.Attendances.Include(a => a.Employee).ThenInclude(e => e.Department).SingleOrDefaultAsync(a => a.EmployeeId == CurrentId && a.WorkDate == today, ct)
            ?? throw ApiException.Bad("Bạn chưa chấm công vào hôm nay.");
        if (record.CheckOutAtUtc.HasValue) throw ApiException.Conflict("Bạn đã chấm công ra hôm nay.");
        await ValidateLocation(settings, input.Latitude, input.Longitude, input.AccuracyMeters, input.MotionScore, "CheckOut", ct);
        record.CheckOutAtUtc = DateTime.UtcNow;
        record.CheckoutLatitude = input.Latitude; record.CheckoutLongitude = input.Longitude;
        record.CheckoutAccuracyMeters = input.AccuracyMeters; record.CheckoutMotionScore = input.MotionScore;
        await db.SaveChangesAsync(ct);
        return Views.Attendance(record);
    }

    private async Task ValidateLocation(CompanySettings settings, double lat, double lon, double accuracy, double motion, string operation, CancellationToken ct)
    {
        try { Rules.Location(settings, lat, lon, accuracy, motion); }
        catch (ApiException)
        {
            await RecordFailure(settings, accuracy > settings.MaxAccuracyMeters ? AttendanceIncidentService.GpsInaccurate : AttendanceIncidentService.OutsideOffice, operation, ct);
            throw;
        }
    }

    private async Task RecordFailure(CompanySettings settings, string code, string operation, CancellationToken ct)
    {
        try { await incidents.RecordAsync(CurrentId, settings, code, operation, ct); }
        catch (Exception ex) when (ex is not OperationCanceledException && !ct.IsCancellationRequested)
        {
            // A monitoring failure must preserve the original attendance error, never report a successful check-in.
            logger.LogError(ex, "Could not record attendance failure {ErrorCode}", code);
        }
    }
}
