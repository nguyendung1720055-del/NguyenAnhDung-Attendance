using System.ComponentModel.DataAnnotations;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using NguyenAnhDung.Attendance.Api.Data;
using NguyenAnhDung.Attendance.Api.Models;

namespace NguyenAnhDung.Attendance.Api.Services;

public static class DatabaseInitializer
{
    public static async Task InitializeAsync(IServiceProvider services, IConfiguration configuration)
    {
        using var scope = services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AttendanceDbContext>();
        if (configuration.GetValue("Database:Initialize", true))
        {
            // Reproducible first-run schema for a new coursework database. Never drops existing data.
            await db.Database.EnsureCreatedAsync();
            if (db.Database.IsSqlServer())
            {
                // EnsureCreated does not extend an existing database. Apply only this additive, idempotent upgrade.
                using var stream = typeof(DatabaseInitializer).Assembly.GetManifestResourceStream("NguyenAnhDung.Attendance.Api.UpgradeAttendanceIncidents.sql")
                    ?? throw new InvalidOperationException("Missing embedded attendance-incident upgrade script.");
                using var reader = new StreamReader(stream);
                await db.Database.ExecuteSqlRawAsync(await reader.ReadToEndAsync());
            }
            if (!await db.CompanySettings.AnyAsync()) { db.CompanySettings.Add(new CompanySettings()); await db.SaveChangesAsync(); }
        }
        if (!configuration.GetValue("BootstrapAdmin:Enabled", false)) return;
        var username = configuration["BootstrapAdmin:Username"] ?? "";
        var email = configuration["BootstrapAdmin:Email"] ?? "";
        var password = configuration["BootstrapAdmin:Password"] ?? "";
        var fullName = configuration["BootstrapAdmin:FullName"] ?? "";
        if (!Regex.IsMatch(username, @"^[A-Za-z0-9_.]{3,40}$") || !new EmailAddressAttribute().IsValid(email) || email.Length > 254 || fullName.Trim().Length is < 2 or > 160)
            throw new InvalidOperationException("BootstrapAdmin requires a valid Username, Email and FullName.");
        Rules.Password(password);
        if (await db.Employees.AnyAsync(e => e.Role == Roles.Admin && e.IsActive)) return;
        if (await db.Employees.AnyAsync(e => e.NormalizedEmail == Rules.Normalize(email) || e.NormalizedUsername == Rules.Normalize(username)))
            throw new InvalidOperationException("BootstrapAdmin identity already exists. Bootstrap never promotes an existing account.");
        var user = new Employee { Username = username.Trim(), NormalizedUsername = Rules.Normalize(username), Email = email.Trim(), NormalizedEmail = Rules.Normalize(email), FullName = fullName.Trim(), EmailVerified = true, Role = Roles.Admin };
        user.PasswordHash = scope.ServiceProvider.GetRequiredService<IPasswordHasher<Employee>>().HashPassword(user, password);
        db.Employees.Add(user);
        await db.SaveChangesAsync();
        scope.ServiceProvider.GetRequiredService<ILoggerFactory>().CreateLogger("BootstrapAdmin").LogWarning("An initial admin was created by explicit BootstrapAdmin configuration. Disable BootstrapAdmin after setup; no password is logged.");
    }
}
