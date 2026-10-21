using System.Data;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using NguyenAnhDung.Attendance.Api.Data;
using NguyenAnhDung.Attendance.Api.Models;

namespace NguyenAnhDung.Attendance.Api.Services;

public sealed class AttendanceIncidentService(AttendanceDbContext db, TimeProvider clock)
{
    // One coursework API process. All gather/review operations share the gate and a DB transaction.
    // Multiple API hosts require distributed serialization before using this feature.
    private static readonly SemaphoreSlim Gate = new(1, 1);
    public const string QrInvalidOrExpired = "QrInvalidOrExpired", GpsInaccurate = "GpsInaccurate", OutsideOffice = "OutsideOffice";
    public static string Label(string code) => code switch {
        QrInvalidOrExpired => "QR không hợp lệ hoặc hết hạn",
        GpsInaccurate => "GPS chưa đủ chính xác",
        OutsideOffice => "Ngoài phạm vi văn phòng",
        _ => "Lỗi chấm công"
    };

    public static string SnapshotKey(CompanySettings settings) => Convert.ToHexString(SHA256.HashData(
        Encoding.UTF8.GetBytes(JsonSerializer.Serialize(new {
            settings.Id, settings.OfficeName, settings.Latitude, settings.Longitude,
            settings.RadiusMeters, settings.MaxAccuracyMeters, settings.QrLifetimeSeconds
        }))));

    public async Task RecordAsync(Guid employeeId, CompanySettings settings, string errorCode, string operation, CancellationToken ct)
    {
        await Gate.WaitAsync(ct);
        try
        {
            await using var transaction = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable, ct);
            var now = clock.GetUtcNow().UtcDateTime;
            var since = now.AddMinutes(-5);
            var key = SnapshotKey(settings);
            var attempt = new AttendanceFailureAttempt {
                EmployeeId = employeeId, ErrorCode = errorCode, Operation = operation,
                OfficeSnapshotKey = key, OfficeName = settings.OfficeName, OccurredAtUtc = now
            };
            db.AttendanceFailureAttempts.Add(attempt);
            await db.SaveChangesAsync(ct);
            // Assigned attempts are never reused to create a second incident after review/expiry.
            var recent = await db.AttendanceFailureAttempts.Where(a => a.IncidentId == null
                && a.OfficeSnapshotKey == key && a.ErrorCode == errorCode
                && a.OccurredAtUtc >= since && a.OccurredAtUtc <= now).ToListAsync(ct);
            var incident = await db.AttendanceIncidents.Include(i => i.Participants)
                .Where(i => i.OfficeSnapshotKey == key && i.ErrorCode == errorCode && i.Status == "Open" && i.LastOccurredAtUtc >= since)
                .OrderByDescending(i => i.LastOccurredAtUtc).FirstOrDefaultAsync(ct);
            if (incident is null && recent.Select(a => a.EmployeeId).Distinct().Count() >= 3)
            {
                incident = new AttendanceIncident {
                    ErrorCode = errorCode, OfficeSnapshotKey = key, OfficeName = settings.OfficeName,
                    FirstOccurredAtUtc = recent.Min(a => a.OccurredAtUtc), LastOccurredAtUtc = now
                };
                db.AttendanceIncidents.Add(incident);
            }
            if (incident is not null)
            {
                foreach (var group in recent.GroupBy(a => a.EmployeeId))
                {
                    var participant = incident.Participants.SingleOrDefault(p => p.EmployeeId == group.Key);
                    // A review covers a fixed set of attempts. Never append failures to reviewed evidence.
                    if (participant is not null && participant.Status != "Pending") continue;
                    if (participant is null)
                    {
                        participant = new AttendanceIncidentParticipant {
                            IncidentId = incident.Id, EmployeeId = group.Key,
                            FirstAttemptAtUtc = group.Min(a => a.OccurredAtUtc)
                        };
                        incident.Participants.Add(participant);
                    }
                    participant.LastAttemptAtUtc = group.Max(a => a.OccurredAtUtc);
                    participant.AttemptCount += group.Count();
                    foreach (var item in group) item.IncidentId = incident.Id;
                }
                incident.LastOccurredAtUtc = incident.Participants.Max(p => p.LastAttemptAtUtc);
            }
            await db.SaveChangesAsync(ct);
            await transaction.CommitAsync(ct);
        }
        finally { Gate.Release(); }
    }

    public async Task ReviewAsync(Guid id, IncidentReviewInput input, Guid reviewerId, CancellationToken ct)
    {
        if (input.Status is not ("Approved" or "Rejected") || input.ReviewNote.Trim().Length is < 5 or > 1000
            || input.ParticipantIds.Length == 0 || input.ParticipantIds.Length != input.ParticipantIds.Distinct().Count())
            throw ApiException.Bad("Chọn người cần duyệt, kết quả Approved/Rejected và lý do từ 5–1000 ký tự; không chọn trùng.");
        await Gate.WaitAsync(ct);
        try
        {
            await using var transaction = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable, ct);
            var incident = await db.AttendanceIncidents.Include(i => i.Participants).SingleOrDefaultAsync(i => i.Id == id, ct)
                ?? throw ApiException.Missing();
            var selected = incident.Participants.Where(p => input.ParticipantIds.Contains(p.Id)).ToList();
            // Validate the entire batch before changing even one participant.
            if (selected.Count != input.ParticipantIds.Length) throw ApiException.Bad("Danh sách có người không thuộc sự cố này.");
            if (selected.Any(p => p.EmployeeId == reviewerId)) throw ApiException.Forbidden("Bạn không được tự duyệt giải trình của mình.");
            if (selected.Any(p => p.Status != "Pending")) throw ApiException.Conflict("Có giải trình đã được xử lý. Hãy tải lại danh sách.");
            var now = clock.GetUtcNow().UtcDateTime;
            foreach (var p in selected)
            {
                p.Status = input.Status; p.ReviewNote = input.ReviewNote.Trim();
                p.ReviewerId = reviewerId; p.ReviewedAtUtc = now;
            }
            if (incident.Participants.All(p => p.Status != "Pending")) incident.Status = "Resolved";
            // Approval accepts an explanation only; no attendance timestamp or late flag is changed.
            await db.SaveChangesAsync(ct);
            await transaction.CommitAsync(ct);
        }
        finally { Gate.Release(); }
    }
}
