using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NguyenAnhDung.Attendance.Api.Data;
using NguyenAnhDung.Attendance.Api.Models;
using NguyenAnhDung.Attendance.Api.Services;

namespace NguyenAnhDung.Attendance.Api.Controllers;

[ApiController, Authorize, Route("api/leave-requests")]
public class LeaveRequestsController(AttendanceDbContext db) : ControllerBase
{
    private Guid CurrentId => Guid.Parse(User.FindFirstValue("sub")!);
    private bool IsSupervisor => User.IsInRole(Roles.Admin) || User.IsInRole(Roles.Manager);
    private IQueryable<LeaveRequest> WithNames => db.LeaveRequests.Include(r => r.Employee).Include(r => r.Reviewer);

    [HttpGet]
    public async Task<object> List(CancellationToken ct)
    {
        var query = WithNames.AsNoTracking();
        if (!IsSupervisor) query = query.Where(r => r.EmployeeId == CurrentId);
        return (await query.OrderByDescending(r => r.CreatedAtUtc).ToListAsync(ct)).Select(Views.Leave);
    }

    [HttpPost]
    public async Task<object> Create(LeaveInput input, CancellationToken ct)
    {
        Rules.Leave(input);
        await RejectDuplicateCorrection(input, null, ct);
        var employee = await db.Employees.SingleAsync(e => e.Id == CurrentId, ct);
        var request = new LeaveRequest { EmployeeId = CurrentId, Employee = employee, Type = input.Type, StartDate = input.StartDate, EndDate = input.EndDate, Reason = input.Reason.Trim() };
        db.LeaveRequests.Add(request); await db.SaveChangesAsync(ct);
        return Views.Leave(request);
    }

    [HttpPut("{id:guid}")]
    public async Task<object> Update(Guid id, LeaveInput input, CancellationToken ct)
    {
        Rules.Leave(input);
        var request = await WithNames.SingleOrDefaultAsync(r => r.Id == id, ct) ?? throw ApiException.Missing();
        RequireOwnPending(request);
        await RejectDuplicateCorrection(input, id, ct);
        request.Type = input.Type; request.StartDate = input.StartDate; request.EndDate = input.EndDate; request.Reason = input.Reason.Trim();
        await db.SaveChangesAsync(ct); return Views.Leave(request);
    }

    [HttpDelete("{id:guid}")]
    public async Task<object> Delete(Guid id, CancellationToken ct)
    {
        var request = await db.LeaveRequests.SingleOrDefaultAsync(r => r.Id == id, ct) ?? throw ApiException.Missing();
        RequireOwnPending(request);
        db.LeaveRequests.Remove(request); await db.SaveChangesAsync(ct);
        return new { Message = "Đã xóa đơn đang chờ duyệt." };
    }

    [HttpPatch("{id:guid}/review"), Authorize(Roles = Roles.Supervisors)]
    public async Task<object> Review(Guid id, ReviewInput input, CancellationToken ct)
    {
        if (input.Status is not ("Approved" or "Rejected")) throw ApiException.Bad("Kết quả duyệt phải là Approved hoặc Rejected.");
        var request = await WithNames.SingleOrDefaultAsync(r => r.Id == id, ct) ?? throw ApiException.Missing();
        if (request.EmployeeId == CurrentId) throw ApiException.Forbidden("Bạn không được tự duyệt đơn của mình.");
        if (User.IsInRole(Roles.Manager) && request.Employee.Role != Roles.Employee) throw ApiException.Forbidden("Manager chỉ được duyệt đơn của Employee.");
        if (request.Status != "Pending") throw ApiException.Conflict("Đơn đã được duyệt hoặc từ chối.");
        if (input.Status == "Rejected" && string.IsNullOrWhiteSpace(input.ReviewNote)) throw ApiException.Bad("Vui lòng ghi lý do từ chối.");
        request.Status = input.Status; request.ReviewNote = input.ReviewNote?.Trim(); request.ReviewerId = CurrentId;
        request.Reviewer = await db.Employees.SingleAsync(e => e.Id == CurrentId, ct); request.ReviewedAtUtc = DateTime.UtcNow;
        // Approval records a review only. Attendance timestamps are never fabricated by this endpoint.
        await db.SaveChangesAsync(ct); return Views.Leave(request);
    }

    private void RequireOwnPending(LeaveRequest request)
    {
        if (request.EmployeeId != CurrentId) throw ApiException.Forbidden("Bạn chỉ được sửa hoặc xóa đơn của mình.");
        if (request.Status != "Pending") throw ApiException.Conflict("Chỉ được sửa hoặc xóa đơn đang chờ duyệt.");
    }
    private async Task RejectDuplicateCorrection(LeaveInput input, Guid? excludeId, CancellationToken ct)
    {
        if (input.Type == "Correction" && await db.LeaveRequests.AnyAsync(r => r.Id != excludeId && r.EmployeeId == CurrentId && r.Type == "Correction" && r.StartDate == input.StartDate && r.Status == "Pending", ct))
            throw ApiException.Conflict("Bạn đã có đơn bổ sung công đang chờ duyệt cho ngày này.");
    }
}
