using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using NguyenAnhDung.Attendance.Api.Data;
using Xunit;

namespace NguyenAnhDung.Attendance.Api.Tests;

public class AuthenticationFlowTests
{
    [Fact]
    public async Task Register_requires_email_and_password_plus_single_use_otp_and_enforces_employee_role()
    {
        using var factory = new AttendanceApiFactory();
        using var client = factory.CreateClient();
        await factory.InitializeAsync();
        const string email = "employee@example.test";
        var register = await client.PostAsJsonAsync("/api/auth/register", new {
            username = "employee.test", email, fullName = "Nguyên Anh Dũng", password = "CorrectPassword123!",
            role = "Admin" // Unknown JSON cannot elevate self-registration.
        });
        await Success(register);
        var body = await register.Content.ReadAsStringAsync();
        Assert.DoesNotContain(factory.Emails.Code(email, "VerifyEmail"), body);

        var unverifiedLogin = await client.PostAsJsonAsync("/api/auth/login", new { identifier = "employee.test", password = "CorrectPassword123!" });
        Assert.False(unverifiedLogin.IsSuccessStatusCode);
        await Success(await client.PostAsJsonAsync("/api/auth/verify-email", new { email, code = factory.Emails.Code(email, "VerifyEmail") }));
        var challenge = await Success(await client.PostAsJsonAsync("/api/auth/login", new { identifier = "employee.test", password = "CorrectPassword123!" }));
        var challengeId = challenge.GetProperty("challengeId").GetGuid();
        Assert.False(challenge.TryGetProperty("accessToken", out _));
        var code = factory.Emails.Code(email, "LoginOtp");
        var session = await Success(await client.PostAsJsonAsync("/api/auth/verify-otp", new { challengeId, code }));
        Assert.Equal("Employee", session.GetProperty("user").GetProperty("role").GetString());
        Assert.False((await client.PostAsJsonAsync("/api/auth/verify-otp", new { challengeId, code })).IsSuccessStatusCode);

        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", session.GetProperty("accessToken").GetString());
        await Success(await client.GetAsync("/api/auth/me"));
        Assert.Equal(HttpStatusCode.Forbidden, (await client.GetAsync("/api/employees")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await client.PostAsJsonAsync("/api/departments", new { name = "Phòng giả", description = "test" })).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await client.PostAsync("/api/attendance/qr", null)).StatusCode);

        // Deactivation is checked against live SQL state, even with an unexpired signed JWT.
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AttendanceDbContext>();
            var user = await db.Employees.SingleAsync();
            user.IsActive = false;
            await db.SaveChangesAsync();
        }
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("/api/auth/me")).StatusCode);
    }

    [Fact]
    public async Task Otp_locks_after_five_wrong_attempts_even_when_correct_code_is_later_supplied()
    {
        using var factory = new AttendanceApiFactory();
        using var client = factory.CreateClient();
        await factory.InitializeAsync();
        const string email = "locked@example.test";
        await Success(await client.PostAsJsonAsync("/api/auth/register", new { username = "locked.test", email, fullName = "Nhân viên test", password = "CorrectPassword123!" }));
        await Success(await client.PostAsJsonAsync("/api/auth/verify-email", new { email, code = factory.Emails.Code(email, "VerifyEmail") }));
        var challenge = await Success(await client.PostAsJsonAsync("/api/auth/login", new { identifier = email, password = "CorrectPassword123!" }));
        var challengeId = challenge.GetProperty("challengeId").GetGuid();
        var code = factory.Emails.Code(email, "LoginOtp");
        var wrongCode = code == "000000" ? "000001" : "000000";
        for (var attempt = 0; attempt < 5; attempt++)
            Assert.False((await client.PostAsJsonAsync("/api/auth/verify-otp", new { challengeId, code = wrongCode })).IsSuccessStatusCode);
        Assert.False((await client.PostAsJsonAsync("/api/auth/verify-otp", new { challengeId, code })).IsSuccessStatusCode);
    }

    internal static async Task<JsonElement> Success(HttpResponseMessage response)
    {
        var text = await response.Content.ReadAsStringAsync();
        Assert.True(response.IsSuccessStatusCode, $"HTTP {(int)response.StatusCode}: {text}");
        return JsonDocument.Parse(text).RootElement.Clone();
    }
}
