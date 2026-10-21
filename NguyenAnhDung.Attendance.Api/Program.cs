using System.Security.Claims;
using System.Text;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using NguyenAnhDung.Attendance.Api.Data;
using NguyenAnhDung.Attendance.Api.Models;
using NguyenAnhDung.Attendance.Api.Services;

var builder = WebApplication.CreateBuilder(args);
// Portable logging: running the coursework API must not require Windows EventLog source permissions.
builder.Logging.ClearProviders();
builder.Logging.AddConsole();
if (args.Contains("--export-schema", StringComparer.Ordinal))
{
    // Offline export from the exact SQL Server EF model: no connection, authentication or seed is performed.
    using var schemaDb = new AttendanceDbContext(new DbContextOptionsBuilder<AttendanceDbContext>()
        .UseSqlServer(builder.Configuration.GetConnectionString("DefaultConnection") ?? "Server=localhost;Database=NguyenAnhDungAttendance;Integrated Security=True;TrustServerCertificate=True").Options);
    Console.WriteLine(schemaDb.Database.GenerateCreateScript());
    return;
}
var jwt = builder.Configuration.GetSection("Jwt").Get<JwtOptions>() ?? new();
var email = builder.Configuration.GetSection("Email").Get<EmailOptions>() ?? new();
if (string.IsNullOrWhiteSpace(jwt.Key) || Encoding.UTF8.GetByteCount(jwt.Key) < 32 || string.IsNullOrWhiteSpace(jwt.Issuer) || string.IsNullOrWhiteSpace(jwt.Audience) || jwt.LifetimeMinutes is < 5 or > 1440)
    throw new InvalidOperationException("Set Jwt__Key to a unique random secret of at least 32 bytes; Jwt Issuer/Audience and lifetime 5..1440 minutes are required. Do not commit secrets.");
if (email.DeliveryMethod == "Console")
{
    if (!builder.Environment.IsDevelopment()) throw new InvalidOperationException("Console email is only permitted in Development. Configure SMTP in production.");
}
else if (email.DeliveryMethod != "Smtp" || string.IsNullOrWhiteSpace(email.Host) || !new System.ComponentModel.DataAnnotations.EmailAddressAttribute().IsValid(email.FromAddress) || email.Port is < 1 or > 65535)
    throw new InvalidOperationException("Configure Email__DeliveryMethod=Smtp and Email__Host, Email__Port, Email__FromAddress (plus provider credentials). Console is available only in Development.");
else if (!builder.Environment.IsDevelopment() && !email.UseSsl)
    throw new InvalidOperationException("SMTP TLS (Email__UseSsl=true) is required outside Development.");

builder.Services.AddSingleton(jwt);
builder.Services.AddSingleton(email);
builder.Services.AddSingleton<TokenService>();
builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddScoped<AttendanceIncidentService>();
builder.Services.AddScoped<AuthService>();
builder.Services.AddScoped<IEmailSender, EmailSender>();
builder.Services.AddScoped<IPasswordHasher<Employee>, PasswordHasher<Employee>>();
builder.Services.Configure<PasswordHasherOptions>(o => o.IterationCount = 210000);
builder.Services.AddDbContext<AttendanceDbContext>(options => options.UseSqlServer(
    builder.Configuration.GetConnectionString("DefaultConnection") ?? throw new InvalidOperationException("Missing ConnectionStrings__DefaultConnection.")));
builder.Services.AddControllers().ConfigureApiBehaviorOptions(options => options.InvalidModelStateResponseFactory = context =>
    new BadRequestObjectResult(new { Message = "Dữ liệu không hợp lệ. Kiểm tra các trường bắt buộc và định dạng thông tin." }));
builder.Services.ConfigureHttpJsonOptions(o => o.SerializerOptions.PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase);
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer(options =>
{
    options.MapInboundClaims = false;
    options.TokenValidationParameters = new TokenService(jwt).AccessValidation();
    options.Events = new JwtBearerEvents {
        OnTokenValidated = async context => {
            var principal = context.Principal!;
            if (principal.FindFirstValue("purpose") != "access" || !Guid.TryParse(principal.FindFirstValue("sub"), out var id)) { context.Fail("Invalid access purpose."); return; }
            var db = context.HttpContext.RequestServices.GetRequiredService<AttendanceDbContext>();
            var user = await db.Employees.AsNoTracking().SingleOrDefaultAsync(e => e.Id == id, context.HttpContext.RequestAborted);
            if (user is null || !user.IsActive || !user.EmailVerified) { context.Fail("Inactive account."); return; }
            // Authorization uses the current database role, so demotion/deactivation applies immediately.
            context.Principal = new ClaimsPrincipal(new ClaimsIdentity([
                new Claim("sub", user.Id.ToString()), new Claim("name", user.FullName), new Claim("role", user.Role), new Claim("purpose", "access")
            ], JwtBearerDefaults.AuthenticationScheme, "name", "role"));
        },
        OnChallenge = async context => { context.HandleResponse(); context.Response.StatusCode = 401; context.Response.Headers.WWWAuthenticate = "Bearer"; await context.Response.WriteAsJsonAsync(new { Message = "Phiên đăng nhập không hợp lệ hoặc đã hết hạn. Vui lòng đăng nhập lại." }); },
        OnForbidden = async context => { context.Response.StatusCode = 403; await context.Response.WriteAsJsonAsync(new { Message = "Bạn không có quyền thực hiện thao tác này." }); }
    };
});
builder.Services.AddAuthorization();
builder.Services.AddRateLimiter(options =>
{
    options.AddPolicy("auth", context => RateLimitPartition.GetSlidingWindowLimiter(context.Connection.RemoteIpAddress?.ToString() ?? "unknown", _ => new SlidingWindowRateLimiterOptions {
        PermitLimit = 30, Window = TimeSpan.FromMinutes(1), SegmentsPerWindow = 6, QueueLimit = 0, AutoReplenishment = true
    }));
    options.OnRejected = async (context, ct) => {
        context.HttpContext.Response.StatusCode = 429;
        context.HttpContext.Response.Headers.RetryAfter = "60";
        await context.HttpContext.Response.WriteAsJsonAsync(new { Message = "Bạn gửi yêu cầu quá nhanh. Vui lòng thử lại sau một phút." }, ct);
    };
});

var app = builder.Build();
app.UseMiddleware<ErrorMiddleware>();
app.UseRouting();
app.UseRateLimiter();
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();
app.MapGet("/health", async (AttendanceDbContext db, CancellationToken ct) =>
    await db.Database.CanConnectAsync(ct) ? Results.Ok(new { Status = "healthy", Application = "NguyenAnhDung.Attendance.Api" }) : Results.Json(new { Status = "unhealthy" }, statusCode: 503));
await DatabaseInitializer.InitializeAsync(app.Services, app.Configuration);
await app.RunAsync();

public partial class Program { }
