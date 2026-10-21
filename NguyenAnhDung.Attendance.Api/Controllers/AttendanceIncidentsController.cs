using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NguyenAnhDung.Attendance.Api.Data;
using NguyenAnhDung.Attendance.Api.Models;
using NguyenAnhDung.Attendance.Api.Services;

namespace NguyenAnhDung.Attendance.Api.Controllers;

[ApiController, Authorize, Route("api/attendance-incidents")]
public class AttendanceIncidentsController(AttendanceDbContext db, AttendanceIncidentService incidents) : ControllerBase
{
    private Guid CurrentId => Guid.Parse(User.FindFirstValue("sub")!);
    private bool IsSupervisor => User.IsInRole(Roles.Admin) || User.IsInRole(Roles.Manager);
    private IQueryable<AttendanceIncident> Visible => (IsSupervisor ? db.AttendanceIncidents :
        db.AttendanceIncidents.Where(i => i.Participants.Any(p => p.EmployeeId == CurrentId)));

    [HttpGet]
    public async Task<IEnumerable<IncidentSummary>> List(CancellationToken ct)
    {
        var rows = await Visible.AsNoTracking().Include(i => i.Participants).OrderByDescending(i => i.LastOccurredAtUtc).ToListAsync(ct);
        return rows.Select(Summary);
    }

    [HttpGet("{id:guid}")]
    public async Task<IncidentDetail> Detail(Guid id, CancellationToken ct)
    {
        var incident = await Visible.AsNoTracking().SingleOrDefaultAsync(i => i.Id == id, ct) ?? throw ApiException.Missing();
        // Aggregate counts are shared; identities and review notes are restricted to the current employee.
        var all = await db.AttendanceIncidentParticipants.AsNoTracking().Where(p => p.IncidentId == id).ToListAsync(ct);
        incident.Participants = all;
        var visibleParticipants = db.AttendanceIncidentParticipants.AsNoTracking().Where(p => p.IncidentId == id);
        if (!IsSupervisor) visibleParticipants = visibleParticipants.Where(p => p.EmployeeId == CurrentId);
        var participants = await visibleParticipants.Include(p => p.Employee).Include(p => p.Reviewer).OrderBy(p => p.FirstAttemptAtUtc).ToListAsync(ct);
        var s = Summary(incident);
        return new IncidentDetail(s.Id, s.ErrorCode, s.ErrorLabel, s.OfficeName, s.FirstOccurredAtUtc, s.LastOccurredAtUtc,
            s.AffectedEmployeeCount, s.PendingCount, s.Status, s.MyReviewStatus,
            participants.Select(p => new IncidentParticipantView(p.Id, p.EmployeeId, p.Employee.FullName, p.Employee.Username,
                p.FirstAttemptAtUtc, p.LastAttemptAtUtc, p.AttemptCount, p.Status, p.ReviewNote, p.ReviewedAtUtc, p.Reviewer?.FullName)));
    }

    [HttpPost("{id:guid}/review"), Authorize(Roles = Roles.Supervisors)]
    public async Task<IncidentDetail> Review(Guid id, IncidentReviewInput input, CancellationToken ct)
    {
        await incidents.ReviewAsync(id, input, CurrentId, ct);
        return await Detail(id, ct);
    }

    private IncidentSummary Summary(AttendanceIncident incident) => new(incident.Id, incident.ErrorCode,
        AttendanceIncidentService.Label(incident.ErrorCode), incident.OfficeName, incident.FirstOccurredAtUtc, incident.LastOccurredAtUtc,
        incident.Participants.Count, incident.Participants.Count(p => p.Status == "Pending"), incident.Status,
        incident.Participants.SingleOrDefault(p => p.EmployeeId == CurrentId)?.Status);
}
