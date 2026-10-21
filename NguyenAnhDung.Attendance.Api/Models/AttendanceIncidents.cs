using System.ComponentModel.DataAnnotations;

namespace NguyenAnhDung.Attendance.Api.Models;

public class AttendanceFailureAttempt
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid EmployeeId { get; set; }
    public Employee Employee { get; set; } = null!;
    public Guid? IncidentId { get; set; }
    public AttendanceIncident? Incident { get; set; }
    [MaxLength(64)] public string OfficeSnapshotKey { get; set; } = "";
    [MaxLength(32)] public string ErrorCode { get; set; } = "";
    [MaxLength(160)] public string OfficeName { get; set; } = "";
    [MaxLength(16)] public string Operation { get; set; } = "";
    public DateTime OccurredAtUtc { get; set; }
    [Timestamp] public byte[] Version { get; set; } = [];
}

public class AttendanceIncident
{
    public Guid Id { get; set; } = Guid.NewGuid();
    [MaxLength(32)] public string ErrorCode { get; set; } = "";
    [MaxLength(64)] public string OfficeSnapshotKey { get; set; } = "";
    [MaxLength(160)] public string OfficeName { get; set; } = "";
    public DateTime FirstOccurredAtUtc { get; set; }
    public DateTime LastOccurredAtUtc { get; set; }
    [MaxLength(16)] public string Status { get; set; } = "Open";
    public ICollection<AttendanceIncidentParticipant> Participants { get; set; } = [];
    [Timestamp] public byte[] Version { get; set; } = [];
}

public class AttendanceIncidentParticipant
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid IncidentId { get; set; }
    public AttendanceIncident Incident { get; set; } = null!;
    public Guid EmployeeId { get; set; }
    public Employee Employee { get; set; } = null!;
    public DateTime FirstAttemptAtUtc { get; set; }
    public DateTime LastAttemptAtUtc { get; set; }
    public int AttemptCount { get; set; }
    [MaxLength(16)] public string Status { get; set; } = "Pending";
    [MaxLength(1000)] public string? ReviewNote { get; set; }
    public Guid? ReviewerId { get; set; }
    public Employee? Reviewer { get; set; }
    public DateTime? ReviewedAtUtc { get; set; }
    [Timestamp] public byte[] Version { get; set; } = [];
}

public record IncidentReviewInput(
    [Required, MinLength(1), MaxLength(200)] Guid[] ParticipantIds,
    [Required] string Status,
    [Required, StringLength(1000, MinimumLength = 5)] string ReviewNote);

public record IncidentSummary(Guid Id, string ErrorCode, string ErrorLabel, string OfficeName,
    DateTime FirstOccurredAtUtc, DateTime LastOccurredAtUtc, int AffectedEmployeeCount,
    int PendingCount, string Status, string? MyReviewStatus);

public record IncidentParticipantView(Guid Id, Guid EmployeeId, string EmployeeName, string Username,
    DateTime FirstAttemptAtUtc, DateTime LastAttemptAtUtc, int AttemptCount, string Status,
    string? ReviewNote, DateTime? ReviewedAtUtc, string? ReviewerName);

public record IncidentDetail(Guid Id, string ErrorCode, string ErrorLabel, string OfficeName,
    DateTime FirstOccurredAtUtc, DateTime LastOccurredAtUtc, int AffectedEmployeeCount,
    int PendingCount, string Status, string? MyReviewStatus, IEnumerable<IncidentParticipantView> Participants);
