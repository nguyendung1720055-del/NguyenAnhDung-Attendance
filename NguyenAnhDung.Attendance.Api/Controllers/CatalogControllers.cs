using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NguyenAnhDung.Attendance.Api.Data;
using NguyenAnhDung.Attendance.Api.Models;
using NguyenAnhDung.Attendance.Api.Services;

namespace NguyenAnhDung.Attendance.Api.Controllers;

[ApiController, Authorize, Route("api/departments")]
public class DepartmentsController(AttendanceDbContext db) : ControllerBase
{
    [HttpGet]
    public async Task<object> List(CancellationToken ct) => (await db.Departments.AsNoTracking().OrderBy(d => d.Name).ToListAsync(ct)).Select(Views.Department);
    [HttpPost, Authorize(Roles = Roles.Admin)]
    public async Task<object> Create(DepartmentInput input, CancellationToken ct)
    {
        Rules.Name(input.Name);
        var department = new Department { Name = input.Name.Trim(), Description = input.Description?.Trim() ?? "" };
        db.Departments.Add(department); await db.SaveChangesAsync(ct);
        return Views.Department(department);
    }
    [HttpPut("{id:guid}"), Authorize(Roles = Roles.Admin)]
    public async Task<object> Update(Guid id, DepartmentInput input, CancellationToken ct)
    {
        Rules.Name(input.Name);
        var department = await db.Departments.FindAsync([id], ct) ?? throw ApiException.Missing();
        department.Name = input.Name.Trim(); department.Description = input.Description?.Trim() ?? "";
        await db.SaveChangesAsync(ct); return Views.Department(department);
    }
    [HttpDelete("{id:guid}"), Authorize(Roles = Roles.Admin)]
    public async Task<object> Delete(Guid id, CancellationToken ct)
    {
        var department = await db.Departments.FindAsync([id], ct) ?? throw ApiException.Missing();
        if (await db.Employees.AnyAsync(e => e.DepartmentId == id, ct)) throw ApiException.Conflict("Phòng ban còn nhân viên, kể cả tài khoản đã ngừng hoạt động.");
        db.Departments.Remove(department); await db.SaveChangesAsync(ct);
        return new { Message = "Đã xóa phòng ban." };
    }
}

[ApiController, Authorize, Route("api/shifts")]
public class ShiftsController(AttendanceDbContext db) : ControllerBase
{
    [HttpGet]
    public async Task<object> List(CancellationToken ct) => (await db.Shifts.AsNoTracking().OrderBy(s => s.StartTime).ToListAsync(ct)).Select(Views.Shift);
    [HttpPost, Authorize(Roles = Roles.Admin)]
    public async Task<object> Create(ShiftInput input, CancellationToken ct)
    {
        Rules.Name(input.Name); var (start, end) = Rules.ShiftTimes(input);
        var shift = new Shift { Name = input.Name.Trim(), StartTime = start, EndTime = end, GraceMinutes = input.GraceMinutes };
        db.Shifts.Add(shift); await db.SaveChangesAsync(ct); return Views.Shift(shift);
    }
    [HttpPut("{id:guid}"), Authorize(Roles = Roles.Admin)]
    public async Task<object> Update(Guid id, ShiftInput input, CancellationToken ct)
    {
        Rules.Name(input.Name); var (start, end) = Rules.ShiftTimes(input);
        var shift = await db.Shifts.FindAsync([id], ct) ?? throw ApiException.Missing();
        shift.Name = input.Name.Trim(); shift.StartTime = start; shift.EndTime = end; shift.GraceMinutes = input.GraceMinutes;
        await db.SaveChangesAsync(ct); return Views.Shift(shift);
    }
    [HttpDelete("{id:guid}"), Authorize(Roles = Roles.Admin)]
    public async Task<object> Delete(Guid id, CancellationToken ct)
    {
        var shift = await db.Shifts.FindAsync([id], ct) ?? throw ApiException.Missing();
        if (await db.Employees.AnyAsync(e => e.ShiftId == id, ct)) throw ApiException.Conflict("Ca làm đang được gán cho nhân viên.");
        db.Shifts.Remove(shift); await db.SaveChangesAsync(ct); return new { Message = "Đã xóa ca làm." };
    }
}

[ApiController, Authorize, Route("api/company-settings")]
public class CompanySettingsController(AttendanceDbContext db) : ControllerBase
{
    [HttpGet]
    public async Task<object> Get(CancellationToken ct) => Views.Settings(await db.CompanySettings.AsNoTracking().SingleAsync(s => s.Id == 1, ct));
    [HttpPut, Authorize(Roles = Roles.Admin)]
    public async Task<object> Update(SettingsInput input, CancellationToken ct)
    {
        Rules.Settings(input);
        var settings = await db.CompanySettings.SingleAsync(s => s.Id == 1, ct);
        settings.OfficeName = input.OfficeName.Trim(); settings.Latitude = input.Latitude; settings.Longitude = input.Longitude;
        settings.RadiusMeters = input.RadiusMeters; settings.MaxAccuracyMeters = input.MaxAccuracyMeters; settings.QrLifetimeSeconds = input.QrLifetimeSeconds;
        await db.SaveChangesAsync(ct); return Views.Settings(settings);
    }
}
