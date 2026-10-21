using System.Collections.Concurrent;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using NguyenAnhDung.Attendance.Api.Data;
using NguyenAnhDung.Attendance.Api.Models;
using NguyenAnhDung.Attendance.Api.Services;

namespace NguyenAnhDung.Attendance.Api.Tests;

// SQLite verifies HTTP/business flows without requiring SQL Server on the test machine.
// SQL Server rowversion/race behavior still requires the real SQL Server demo checklist.
public sealed class AttendanceApiFactory : WebApplicationFactory<Program>
{
    private readonly SqliteConnection connection = new("Data Source=:memory:");
    public CapturedEmailSender Emails { get; } = new();
    public AdjustableTimeProvider Clock { get; } = new();

    public AttendanceApiFactory() => connection.Open();

    private static Dictionary<string, string?> TestConfiguration() => new() {
        ["Database:Initialize"] = "false",
        ["BootstrapAdmin:Enabled"] = "false",
        ["Jwt:Key"] = "Tests-only-key-for-integration-1234567890-do-not-use-in-production!",
        ["Email:DeliveryMethod"] = "Console",
        ["ConnectionStrings:DefaultConnection"] = "Server=localhost;Database=NguyenAnhDungAttendance;Trusted_Connection=True;TrustServerCertificate=True"
    };

    protected override IHost CreateHost(IHostBuilder builder)
    {
        // Minimal hosting reads startup settings before ConfigureWebHost callbacks.
        // Host configuration is supplied to CreateBuilder early, without global env changes.
        builder.ConfigureHostConfiguration(config => config.AddInMemoryCollection(TestConfiguration()));
        return base.CreateHost(builder);
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Development");
        builder.ConfigureLogging(logging => logging.ClearProviders().AddConsole());
        builder.ConfigureAppConfiguration((_, config) => config.AddInMemoryCollection(TestConfiguration()));
        builder.ConfigureServices(services => {
            services.RemoveAll<AttendanceDbContext>();
            services.AddScoped<AttendanceDbContext>(_ => new TestAttendanceDbContext(
                new DbContextOptionsBuilder<AttendanceDbContext>().UseSqlite(connection).Options));
            services.RemoveAll<IEmailSender>();
            services.AddSingleton<IEmailSender>(Emails);
            services.RemoveAll<TimeProvider>();
            services.AddSingleton<TimeProvider>(Clock);
        });
    }

    public async Task InitializeAsync()
    {
        using var scope = Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AttendanceDbContext>();
        await db.Database.EnsureCreatedAsync();
        db.CompanySettings.Add(new CompanySettings());
        await db.SaveChangesAsync();
    }

    protected override void Dispose(bool disposing)
    {
        base.Dispose(disposing);
        if (disposing) connection.Dispose();
    }

    private sealed class TestAttendanceDbContext(DbContextOptions<AttendanceDbContext> options) : AttendanceDbContext(options)
    {
        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            base.OnModelCreating(modelBuilder);
            foreach (var entity in modelBuilder.Model.GetEntityTypes())
            {
                if (entity.FindProperty("Version") is { } version)
                    version.ValueGenerated = Microsoft.EntityFrameworkCore.Metadata.ValueGenerated.Never;
            }
        }
    }
}

public sealed class AdjustableTimeProvider : TimeProvider
{
    public DateTimeOffset Now { get; set; } = DateTimeOffset.UtcNow;
    public override DateTimeOffset GetUtcNow() => Now;
}

public sealed class CapturedEmailSender : IEmailSender
{
    private readonly ConcurrentDictionary<(string, string), string> codes = new();
    public string Code(string email, string purpose) => codes[(email.ToUpperInvariant(), purpose)];
    public Task SendCodeAsync(string email, string code, string purpose, CancellationToken ct)
    {
        codes[(email.ToUpperInvariant(), purpose)] = code;
        return Task.CompletedTask;
    }
}
