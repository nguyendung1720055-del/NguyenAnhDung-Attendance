using System.ComponentModel.DataAnnotations;

namespace NguyenAnhDung.Attendance.Api.Models;

public static class Roles
{
    public const string Admin = "Admin", Manager = "Manager", Employee = "Employee";
    public const string Supervisors = Admin + "," + Manager;
    public static bool IsValid(string role) => role is Admin or Manager or Employee;
}

public class Employee
{
    public Guid Id { get; set; } = Guid.NewGuid();
    [MaxLength(40)] public string Username { get; set; } = "";
    [MaxLength(40)] public string NormalizedUsername { get; set; } = "";
    [MaxLength(254)] public string Email { get; set; } = "";
    [MaxLength(254)] public string NormalizedEmail { get; set; } = "";
    [MaxLength(160)] public string FullName { get; set; } = "";
    public string PasswordHash { get; set; } = "";
    [MaxLength(16)] public string Role { get; set; } = Roles.Employee;
    public Guid? DepartmentId { get; set; }
    public Department? Department { get; set; }
    public Guid? ShiftId { get; set; }
    public Shift? Shift { get; set; }
    public bool IsActive { get; set; } = true;
    public bool EmailVerified { get; set; }
    public int FailedLoginAttempts { get; set; }
    public DateTime? LockedUntilUtc { get; set; }
    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
    [Timestamp] public byte[] Version { get; set; } = [];
}

public class Department
{
    public Guid Id { get; set; } = Guid.NewGuid();
    [MaxLength(120)] public string Name { get; set; } = "";
    [MaxLength(600)] public string Description { get; set; } = "";
}

public class Shift
{
    public Guid Id { get; set; } = Guid.NewGuid();
    [MaxLength(120)] public string Name { get; set; } = "";
    public TimeOnly StartTime { get; set; }
    public TimeOnly EndTime { get; set; }
    public int GraceMinutes { get; set; }
}

public class EmailChallenge
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid EmployeeId { get; set; }
    public Employee Employee { get; set; } = null!;
    [MaxLength(20)] public string Purpose { get; set; } = "";
    [MaxLength(64)] public string CodeHash { get; set; } = "";
    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
    public DateTime ExpiresAtUtc { get; set; }
    public int Attempts { get; set; }
    public bool Consumed { get; set; }
    [Timestamp] public byte[] Version { get; set; } = [];
}

public class Attendance
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid EmployeeId { get; set; }
    public Employee Employee { get; set; } = null!;
    public DateOnly WorkDate { get; set; }
    public DateTime CheckInAtUtc { get; set; }
    public DateTime? CheckOutAtUtc { get; set; }
    public bool IsLate { get; set; }
    public double Latitude { get; set; }
    public double Longitude { get; set; }
    public double AccuracyMeters { get; set; }
    public double MotionScore { get; set; }
    public double? CheckoutLatitude { get; set; }
    public double? CheckoutLongitude { get; set; }
    public double? CheckoutAccuracyMeters { get; set; }
    public double? CheckoutMotionScore { get; set; }
    [Timestamp] public byte[] Version { get; set; } = [];
}

public class LeaveRequest
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid EmployeeId { get; set; }
    public Employee Employee { get; set; } = null!;
    [MaxLength(16)] public string Type { get; set; } = "Annual";
    public DateOnly StartDate { get; set; }
    public DateOnly EndDate { get; set; }
    [MaxLength(2000)] public string Reason { get; set; } = "";
    [MaxLength(16)] public string Status { get; set; } = "Pending";
    [MaxLength(1000)] public string? ReviewNote { get; set; }
    public Guid? ReviewerId { get; set; }
    public Employee? Reviewer { get; set; }
    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
    public DateTime? ReviewedAtUtc { get; set; }
    [Timestamp] public byte[] Version { get; set; } = [];
}

public class CompanySettings
{
    public int Id { get; set; } = 1;
    [MaxLength(160)] public string OfficeName { get; set; } = "Văn phòng Hữu Duyên";
    public double Latitude { get; set; } = 10.7769;
    public double Longitude { get; set; } = 106.7009;
    public double RadiusMeters { get; set; } = 150;
    public double MaxAccuracyMeters { get; set; } = 60;
    public int QrLifetimeSeconds { get; set; } = 60;
    [Timestamp] public byte[] Version { get; set; } = [];
}
