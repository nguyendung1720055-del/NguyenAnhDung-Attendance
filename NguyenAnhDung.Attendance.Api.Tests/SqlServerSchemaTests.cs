using System.Text.RegularExpressions;
using Microsoft.EntityFrameworkCore;
using NguyenAnhDung.Attendance.Api.Data;
using Xunit;

namespace NguyenAnhDung.Attendance.Api.Tests;

public class SqlServerSchemaTests
{
    [Fact]
    public void Fixed_company_settings_key_can_be_seeded_without_identity_insert()
    {
        // Generate SQL with the production provider; SQLite permits explicit identity
        // values and cannot detect SQL Server's IDENTITY_INSERT restriction.
        using var db = new AttendanceDbContext(new DbContextOptionsBuilder<AttendanceDbContext>()
            .UseSqlServer("Server=localhost;Database=NguyenAnhDungAttendance;Integrated Security=True;TrustServerCertificate=True").Options);
        var sql = db.Database.GenerateCreateScript();
        var companyTable = Regex.Match(sql, @"CREATE TABLE \[CompanySettings\] \((.*?)\);", RegexOptions.Singleline);
        Assert.True(companyTable.Success);
        Assert.Contains("[Id] int NOT NULL", companyTable.Value);
        Assert.DoesNotContain("IDENTITY", companyTable.Value);
        Assert.Contains("CREATE UNIQUE INDEX [IX_Attendances_EmployeeId_WorkDate]", sql);
        Assert.Contains("[Version] rowversion NOT NULL", sql);
    }
}
