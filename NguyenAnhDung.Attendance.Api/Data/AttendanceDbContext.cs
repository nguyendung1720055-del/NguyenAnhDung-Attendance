using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage.ValueConversion;
using NguyenAnhDung.Attendance.Api.Models;
using AttendanceRecord = NguyenAnhDung.Attendance.Api.Models.Attendance;

namespace NguyenAnhDung.Attendance.Api.Data;

public class AttendanceDbContext(DbContextOptions<AttendanceDbContext> options) : DbContext(options)
{
    public DbSet<Employee> Employees => Set<Employee>();
    public DbSet<Department> Departments => Set<Department>();
    public DbSet<Shift> Shifts => Set<Shift>();
    public DbSet<EmailChallenge> EmailChallenges => Set<EmailChallenge>();
    public DbSet<AttendanceRecord> Attendances => Set<AttendanceRecord>();
    public DbSet<LeaveRequest> LeaveRequests => Set<LeaveRequest>();
    public DbSet<CompanySettings> CompanySettings => Set<CompanySettings>();
    public DbSet<AttendanceFailureAttempt> AttendanceFailureAttempts => Set<AttendanceFailureAttempt>();
    public DbSet<AttendanceIncident> AttendanceIncidents => Set<AttendanceIncident>();
    public DbSet<AttendanceIncidentParticipant> AttendanceIncidentParticipants => Set<AttendanceIncidentParticipant>();

    protected override void OnModelCreating(ModelBuilder b)
    {
        // Singleton settings always uses key 1; SQL Server must not make this key an IDENTITY column.
        b.Entity<CompanySettings>().Property(s => s.Id).ValueGeneratedNever();
        b.Entity<Employee>().HasIndex(e => e.NormalizedUsername).IsUnique();
        b.Entity<Employee>().HasIndex(e => e.NormalizedEmail).IsUnique();
        b.Entity<Employee>().HasOne(e => e.Department).WithMany().OnDelete(DeleteBehavior.Restrict);
        b.Entity<Employee>().HasOne(e => e.Shift).WithMany().OnDelete(DeleteBehavior.Restrict);
        b.Entity<Department>().HasIndex(e => e.Name).IsUnique();
        b.Entity<Shift>().HasIndex(e => e.Name).IsUnique();
        b.Entity<AttendanceRecord>().HasIndex(a => new { a.EmployeeId, a.WorkDate }).IsUnique();
        b.Entity<AttendanceRecord>().HasOne(a => a.Employee).WithMany().OnDelete(DeleteBehavior.Restrict);
        b.Entity<EmailChallenge>().HasIndex(c => new { c.EmployeeId, c.Purpose, c.CreatedAtUtc });
        b.Entity<EmailChallenge>().HasOne(c => c.Employee).WithMany().OnDelete(DeleteBehavior.Cascade);
        b.Entity<LeaveRequest>().HasOne(r => r.Employee).WithMany().OnDelete(DeleteBehavior.Restrict);
        b.Entity<LeaveRequest>().HasOne(r => r.Reviewer).WithMany().OnDelete(DeleteBehavior.Restrict);
        b.Entity<LeaveRequest>().HasIndex(r => new { r.EmployeeId, r.StartDate });
        b.Entity<AttendanceFailureAttempt>().HasOne(a => a.Employee).WithMany().OnDelete(DeleteBehavior.Restrict);
        b.Entity<AttendanceFailureAttempt>().HasOne(a => a.Incident).WithMany().OnDelete(DeleteBehavior.Restrict);
        b.Entity<AttendanceFailureAttempt>().HasIndex(a => new { a.OfficeSnapshotKey, a.ErrorCode, a.OccurredAtUtc });
        b.Entity<AttendanceIncident>().HasIndex(i => new { i.OfficeSnapshotKey, i.ErrorCode, i.LastOccurredAtUtc });
        b.Entity<AttendanceIncidentParticipant>().HasOne(p => p.Incident).WithMany(i => i.Participants).OnDelete(DeleteBehavior.Restrict);
        b.Entity<AttendanceIncidentParticipant>().HasOne(p => p.Employee).WithMany().OnDelete(DeleteBehavior.Restrict);
        b.Entity<AttendanceIncidentParticipant>().HasOne(p => p.Reviewer).WithMany().OnDelete(DeleteBehavior.Restrict);
        b.Entity<AttendanceIncidentParticipant>().HasIndex(p => new { p.IncidentId, p.EmployeeId }).IsUnique();
        // SQL Server datetime2 does not retain DateTime.Kind. All timestamp columns in this app are UTC.
        var utcConverter = new ValueConverter<DateTime, DateTime>(v => v, v => DateTime.SpecifyKind(v, DateTimeKind.Utc));
        foreach (var property in b.Model.GetEntityTypes().SelectMany(t => t.GetProperties()))
            if (property.ClrType == typeof(DateTime) || property.ClrType == typeof(DateTime?)) property.SetValueConverter(utcConverter);
    }
}
