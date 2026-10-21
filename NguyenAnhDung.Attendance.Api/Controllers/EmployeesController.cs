using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NguyenAnhDung.Attendance.Api.Data;
using NguyenAnhDung.Attendance.Api.Models;
using NguyenAnhDung.Attendance.Api.Services;

namespace NguyenAnhDung.Attendance.Api.Controllers;

[ApiController, Route("api/employees"), Authorize(Roles = Roles.Supervisors)]
public class EmployeesController(AttendanceDbContext db, AuthService auth) : ControllerBase
{
    private Guid CurrentId => Guid.Parse(User.FindFirstValue("sub")!);
    [HttpGet]
    public async Task<object> List(CancellationToken ct) => (await db.Employees.AsNoTracking().OrderBy(e => e.FullName).ToListAsync(ct)).Select(UserView.From);

    [HttpPost, Authorize(Roles = Roles.Admin)]
    public async Task<object> Create(CreateEmployeeInput input, CancellationToken ct)
    {
        await ValidateAssignment(input.Role, input.DepartmentId, input.ShiftId, ct);
        var employee = await auth.RegisterAsync(new(input.Username, input.Email, input.FullName, input.Password), ct, input.Role, input.DepartmentId, input.ShiftId);
        return UserView.From(employee);
    }

    [HttpPut("{id:guid}"), Authorize(Roles = Roles.Admin)]
    public async Task<object> Update(Guid id, UpdateEmployeeInput input, CancellationToken ct)
    {
        Rules.Name(input.FullName);
        await ValidateAssignment(input.Role, input.DepartmentId, input.ShiftId, ct);
        // Serializable count + update prevents concurrent admins from removing the final active admin.
        await using var transaction = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable, ct);
        var user = await db.Employees.SingleOrDefaultAsync(e => e.Id == id, ct) ?? throw ApiException.Missing();
        await ProtectAdmin(user, input.Role, input.IsActive, ct);
        user.FullName = input.FullName.Trim(); user.Role = input.Role; user.IsActive = input.IsActive;
        user.DepartmentId = input.DepartmentId; user.ShiftId = input.ShiftId;
        await db.SaveChangesAsync(ct); await transaction.CommitAsync(ct);
        return UserView.From(user);
    }

    [HttpDelete("{id:guid}"), Authorize(Roles = Roles.Admin)]
    public async Task<object> Delete(Guid id, CancellationToken ct)
    {
        await using var transaction = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable, ct);
        var user = await db.Employees.SingleOrDefaultAsync(e => e.Id == id, ct) ?? throw ApiException.Missing();
        await ProtectAdmin(user, user.Role, false, ct);
        user.IsActive = false;
        await db.SaveChangesAsync(ct); await transaction.CommitAsync(ct);
        return new { Message = "Đã ngừng hoạt động tài khoản; lịch sử công vẫn được lưu." };
    }

    private async Task ValidateAssignment(string role, Guid? departmentId, Guid? shiftId, CancellationToken ct)
    {
        if (!Roles.IsValid(role)) throw ApiException.Bad("Vai trò chỉ có thể là Admin, Manager hoặc Employee.");
        if (departmentId.HasValue && !await db.Departments.AnyAsync(d => d.Id == departmentId, ct)) throw ApiException.Bad("Phòng ban không tồn tại.");
        if (shiftId.HasValue && !await db.Shifts.AnyAsync(s => s.Id == shiftId, ct)) throw ApiException.Bad("Ca làm không tồn tại.");
    }

    private async Task ProtectAdmin(Employee user, string nextRole, bool active, CancellationToken ct)
    {
        if (user.Id == CurrentId && (!active || nextRole != Roles.Admin)) throw ApiException.Bad("Bạn không thể tự vô hiệu hóa hoặc hạ quyền quản trị của mình.");
        if (user.Role == Roles.Admin && user.IsActive && (!active || nextRole != Roles.Admin)
            && await db.Employees.CountAsync(e => e.Role == Roles.Admin && e.IsActive, ct) <= 1)
            throw ApiException.Conflict("Hệ thống phải luôn có ít nhất một Admin đang hoạt động.");
    }
}
