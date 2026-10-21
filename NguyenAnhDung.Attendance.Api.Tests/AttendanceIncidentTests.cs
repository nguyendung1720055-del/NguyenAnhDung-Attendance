using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using NguyenAnhDung.Attendance.Api.Data;
using NguyenAnhDung.Attendance.Api.Models;
using NguyenAnhDung.Attendance.Api.Services;
using Xunit;
using static NguyenAnhDung.Attendance.Api.Tests.AuthenticationFlowTests;

namespace NguyenAnhDung.Attendance.Api.Tests;

public class AttendanceIncidentTests
{
    [Theory]
    [InlineData("QrInvalidOrExpired")]
    [InlineData("GpsInaccurate")]
    [InlineData("OutsideOffice")]
    public async Task Correlation_requires_three_distinct_recent_employees_and_uses_server_clock(string code)
    {
        using var f = new AttendanceApiFactory(); await f.InitializeAsync();
        var one = await Actor(f, "one"); var two = await Actor(f, "two"); var three = await Actor(f, "three");
        using var c1 = Client(f, one); using var c2 = Client(f, two); using var c3 = Client(f, three);
        for (var n = 0; n < 5; n++) await Fail(f, c1, code);
        await Fail(f, c2, code);
        Assert.Empty((await Success(await c1.GetAsync("/api/attendance-incidents"))).EnumerateArray());
        f.Clock.Now = f.Clock.Now.AddMinutes(6);
        await Fail(f, c3, code);
        Assert.Empty((await Success(await c3.GetAsync("/api/attendance-incidents"))).EnumerateArray());
        await Fail(f, c1, code); await Fail(f, c2, code);
        var summary = (await Success(await c1.GetAsync("/api/attendance-incidents")))[0];
        Assert.Equal(code, summary.GetProperty("errorCode").GetString());
        Assert.Equal(3, summary.GetProperty("affectedEmployeeCount").GetInt32());
        Assert.Equal(f.Clock.Now.UtcDateTime, summary.GetProperty("firstOccurredAtUtc").GetDateTime());
        Assert.Equal("Pending", summary.GetProperty("myReviewStatus").GetString());
        var detail = await Success(await c1.GetAsync($"/api/attendance-incidents/{summary.GetProperty("id").GetGuid()}"));
        var p = Assert.Single(detail.GetProperty("participants").EnumerateArray());
        Assert.Equal(1, p.GetProperty("attemptCount").GetInt32());
        using var scope = f.Services.CreateScope(); var db = scope.ServiceProvider.GetRequiredService<AttendanceDbContext>();
        Assert.Equal(9, await db.AttendanceFailureAttempts.CountAsync());
        Assert.Equal(3, await db.AttendanceFailureAttempts.CountAsync(a => a.IncidentId != null));
        Assert.Equal(0, await db.Attendances.CountAsync());
    }

    [Fact]
    public async Task Different_error_codes_and_office_settings_do_not_form_a_false_cluster()
    {
        using var f = new AttendanceApiFactory(); await f.InitializeAsync();
        var one = await Actor(f, "one"); var two = await Actor(f, "two"); var three = await Actor(f, "three");
        using var c1 = Client(f, one); using var c2 = Client(f, two); using var c3 = Client(f, three);
        await Fail(f, c1, "QrInvalidOrExpired"); await Fail(f, c2, "GpsInaccurate"); await Fail(f, c3, "OutsideOffice");
        await Fail(f, c1, "GpsInaccurate");
        using (var scope = f.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AttendanceDbContext>();
            (await db.CompanySettings.SingleAsync()).RadiusMeters = 250;
            await db.SaveChangesAsync();
        }
        await Fail(f, c3, "GpsInaccurate");
        Assert.Empty((await Success(await c1.GetAsync("/api/attendance-incidents"))).EnumerateArray());
        await Fail(f, c1, "GpsInaccurate"); await Fail(f, c2, "GpsInaccurate");
        var rows = await Success(await c1.GetAsync("/api/attendance-incidents"));
        Assert.Single(rows.EnumerateArray());
        Assert.Equal("GpsInaccurate", rows[0].GetProperty("errorCode").GetString());
    }

    [Fact]
    public async Task Incident_privacy_batch_review_self_review_and_replay_are_enforced_without_rewriting_attendance()
    {
        using var f = new AttendanceApiFactory(); await f.InitializeAsync();
        var admin = await Actor(f, "admin", Roles.Admin); var manager = await Actor(f, "manager", Roles.Manager);
        var one = await Actor(f, "one"); var two = await Actor(f, "two"); var outsider = await Actor(f, "outsider");
        using var ac = Client(f, admin); using var mc = Client(f, manager); using var c1 = Client(f, one); using var c2 = Client(f, two); using var oc = Client(f, outsider);
        await Fail(f, c1, "OutsideOffice"); await Fail(f, c2, "OutsideOffice"); await Fail(f, mc, "OutsideOffice");
        var row = (await Success(await ac.GetAsync("/api/attendance-incidents")))[0]; var id = row.GetProperty("id").GetGuid();
        var path = $"/api/attendance-incidents/{id}";
        using var anonymous = f.CreateClient(); Assert.Equal(HttpStatusCode.Unauthorized, (await anonymous.GetAsync(path)).StatusCode);
        Assert.Empty((await Success(await oc.GetAsync("/api/attendance-incidents"))).EnumerateArray());
        Assert.Equal(HttpStatusCode.NotFound, (await oc.GetAsync(path)).StatusCode);
        var own = await Success(await c1.GetAsync(path));
        Assert.Equal(one.Id, Assert.Single(own.GetProperty("participants").EnumerateArray()).GetProperty("employeeId").GetGuid());
        Assert.DoesNotContain(two.Username, own.GetRawText());
        var detail = await Success(await mc.GetAsync(path));
        var participants = detail.GetProperty("participants").EnumerateArray().ToArray();
        Guid Participant(Employee employee) => participants.Single(p => p.GetProperty("employeeId").GetGuid() == employee.Id).GetProperty("id").GetGuid();
        var p1 = Participant(one); var p2 = Participant(two); var pm = Participant(manager);
        object Payload(params Guid[] ids) => new { participantIds = ids, status = "Approved", reviewNote = "Đã đối chiếu sự cố chung" };
        Assert.Equal(HttpStatusCode.Forbidden, (await c1.PostAsJsonAsync(path + "/review", Payload(p1))).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await mc.PostAsJsonAsync(path + "/review", Payload(p1, pm))).StatusCode);
        Assert.Equal(3, (await Success(await ac.GetAsync(path))).GetProperty("pendingCount").GetInt32());
        Assert.Equal(HttpStatusCode.BadRequest, (await mc.PostAsJsonAsync(path + "/review", Payload(p1, Guid.NewGuid()))).StatusCode);
        // Valid attendance is created separately after the failed attempt, then must survive approval unchanged.
        var qr = f.Services.GetRequiredService<TokenService>().Qr(60, admin.Id).Token;
        var before = await Success(await c1.PostAsJsonAsync("/api/attendance/check-in", new { qrToken = qr, latitude = 10.7769, longitude = 106.7009, accuracyMeters = 10, motionScore = .1 }));
        await Success(await mc.PostAsJsonAsync(path + "/review", Payload(p1)));
        Assert.Equal(HttpStatusCode.Conflict, (await mc.PostAsJsonAsync(path + "/review", Payload(p1, p2))).StatusCode);
        Assert.Equal(2, (await Success(await ac.GetAsync(path))).GetProperty("pendingCount").GetInt32());
        await Success(await mc.PostAsJsonAsync(path + "/review", Payload(p2)));
        var resolved = await Success(await ac.PostAsJsonAsync(path + "/review", Payload(pm)));
        Assert.Equal("Resolved", resolved.GetProperty("status").GetString());
        Assert.Equal(0, resolved.GetProperty("pendingCount").GetInt32());
        var reviewed = (await Success(await c1.GetAsync(path))).GetProperty("participants")[0];
        Assert.Equal("Approved", reviewed.GetProperty("status").GetString());
        Assert.Equal(manager.FullName, reviewed.GetProperty("reviewerName").GetString());
        Assert.Equal("Đã đối chiếu sự cố chung", reviewed.GetProperty("reviewNote").GetString());
        var after = (await Success(await c1.GetAsync("/api/attendance")))[0];
        Assert.Equal(before.GetProperty("checkInAtUtc").GetDateTime(), after.GetProperty("checkInAtUtc").GetDateTime());
        Assert.Equal(before.GetProperty("isLate").GetBoolean(), after.GetProperty("isLate").GetBoolean());
        Assert.Equal(JsonValueKind.Null, after.GetProperty("checkOutAtUtc").ValueKind);
    }

    [Fact]
    public async Task Resolved_attempts_are_not_reused_and_malformed_or_ineligible_requests_are_not_counted()
    {
        using var f = new AttendanceApiFactory(); await f.InitializeAsync();
        var admin = await Actor(f, "admin", Roles.Admin); var one = await Actor(f, "one"); var two = await Actor(f, "two"); var three = await Actor(f, "three");
        using var ac = Client(f, admin); using var c1 = Client(f, one); using var c2 = Client(f, two); using var c3 = Client(f, three);
        Assert.Equal(HttpStatusCode.BadRequest, (await c1.PostAsJsonAsync("/api/attendance/check-in", new { qrToken = "bad", latitude = 999, longitude = 0, accuracyMeters = 10, motionScore = .1 })).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await c1.PostAsJsonAsync("/api/attendance/check-out", new { latitude = 0, longitude = 0, accuracyMeters = 10, motionScore = .1 })).StatusCode);
        using (var scope = f.Services.CreateScope()) Assert.Empty(await scope.ServiceProvider.GetRequiredService<AttendanceDbContext>().AttendanceFailureAttempts.ToListAsync());
        await Fail(f, c1, "QrInvalidOrExpired"); await Fail(f, c2, "QrInvalidOrExpired"); await Fail(f, c3, "QrInvalidOrExpired");
        var id = (await Success(await ac.GetAsync("/api/attendance-incidents")))[0].GetProperty("id").GetGuid();
        var p = (await Success(await ac.GetAsync($"/api/attendance-incidents/{id}"))).GetProperty("participants").EnumerateArray().Select(x => x.GetProperty("id").GetGuid()).ToArray();
        await Success(await ac.PostAsJsonAsync($"/api/attendance-incidents/{id}/review", new { participantIds = p, status = "Rejected", reviewNote = "Chưa đủ cơ sở giải trình" }));
        await Fail(f, c1, "QrInvalidOrExpired");
        Assert.Single((await Success(await ac.GetAsync("/api/attendance-incidents"))).EnumerateArray());
        await Fail(f, c2, "QrInvalidOrExpired"); await Fail(f, c3, "QrInvalidOrExpired");
        Assert.Equal(2, (await Success(await ac.GetAsync("/api/attendance-incidents"))).GetArrayLength());
        var qr = f.Services.GetRequiredService<TokenService>().Qr(60, admin.Id).Token;
        await Success(await c1.PostAsJsonAsync("/api/attendance/check-in", new { qrToken = qr, latitude = 10.7769, longitude = 106.7009, accuracyMeters = 10, motionScore = .1 }));
        // Already checked in => duplicate check-in is rejected before counting its invalid QR.
        Assert.Equal(HttpStatusCode.Conflict, (await c1.PostAsJsonAsync("/api/attendance/check-in", new { qrToken = "bad", latitude = 0, longitude = 0, accuracyMeters = 10, motionScore = .1 })).StatusCode);
        using var finalScope = f.Services.CreateScope(); var db = finalScope.ServiceProvider.GetRequiredService<AttendanceDbContext>();
        Assert.Equal(6, await db.AttendanceFailureAttempts.CountAsync());
        // A genuine checkout GPS failure is also collected, without changing checkout time.
        Assert.Equal(HttpStatusCode.BadRequest, (await c1.PostAsJsonAsync("/api/attendance/check-out", new { latitude = 0, longitude = 0, accuracyMeters = 100, motionScore = .1 })).StatusCode);
        Assert.Equal(7, await db.AttendanceFailureAttempts.CountAsync());
        Assert.Null((await db.Attendances.AsNoTracking().SingleAsync()).CheckOutAtUtc);
    }

    private static async Task Fail(AttendanceApiFactory f, HttpClient client, string code)
    {
        var qr = code == "QrInvalidOrExpired" ? "deliberately-invalid-qr" : f.Services.GetRequiredService<TokenService>().Qr(60, Guid.NewGuid()).Token;
        var response = await client.PostAsJsonAsync("/api/attendance/check-in", new {
            qrToken = qr, latitude = code == "OutsideOffice" ? 0 : 10.7769,
            longitude = code == "OutsideOffice" ? 0 : 106.7009, accuracyMeters = code == "GpsInaccurate" ? 100 : 10,
            motionScore = .1, occurredAtUtc = "1999-01-01T00:00:00Z" // ignored; server owns timestamps
        });
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var message = (await response.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("message").GetString();
        Assert.Contains(code == "QrInvalidOrExpired" ? "QR" : code == "GpsInaccurate" ? "GPS" : "ngoài phạm vi", message);
    }

    private static async Task<Employee> Actor(AttendanceApiFactory f, string username, string role = Roles.Employee)
    {
        using var scope = f.Services.CreateScope(); var db = scope.ServiceProvider.GetRequiredService<AttendanceDbContext>();
        var shift = new Shift { Name = "Ca " + username, StartTime = new(8, 0), EndTime = new(17, 0) };
        var employee = new Employee { Username = username, NormalizedUsername = username.ToUpperInvariant(), Email = username + "@test.local", NormalizedEmail = (username + "@test.local").ToUpperInvariant(), FullName = "Người " + username, Role = role, EmailVerified = true, Shift = shift, ShiftId = shift.Id };
        db.Employees.Add(employee); await db.SaveChangesAsync(); return employee;
    }

    private static HttpClient Client(AttendanceApiFactory f, Employee employee)
    {
        var client = f.CreateClient(); client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", f.Services.GetRequiredService<TokenService>().Access(employee).Token); return client;
    }
}
