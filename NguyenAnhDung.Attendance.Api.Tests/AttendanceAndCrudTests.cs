using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using Microsoft.Extensions.DependencyInjection;
using NguyenAnhDung.Attendance.Api.Data;
using NguyenAnhDung.Attendance.Api.Models;
using NguyenAnhDung.Attendance.Api.Services;
using Xunit;
using static NguyenAnhDung.Attendance.Api.Tests.AuthenticationFlowTests;

namespace NguyenAnhDung.Attendance.Api.Tests;

public class AttendanceAndCrudTests
{
    [Fact]
    public async Task Attendance_checks_qr_geofence_uniqueness_ownership_and_checkout_state()
    {
        using var factory = new AttendanceApiFactory();
        await factory.InitializeAsync();
        var admin = await Actor(factory, "admin", Roles.Admin);
        var worker = await Actor(factory, "worker", Roles.Employee);
        var other = await Actor(factory, "other", Roles.Employee);
        using var adminClient = Client(factory, admin);
        using var employeeClient = Client(factory, worker);
        using var otherClient = Client(factory, other);

        var qr = await Success(await adminClient.PostAsync("/api/attendance/qr", null));
        var qrToken = qr.GetProperty("token").GetString();
        Assert.Equal(HttpStatusCode.Unauthorized, (await AnonymousWithToken(factory, qrToken!)).StatusCode);
        var outside = await employeeClient.PostAsJsonAsync("/api/attendance/check-in", new { qrToken, latitude = 0, longitude = 0, accuracyMeters = 10, motionScore = 0.2 });
        Assert.Equal(HttpStatusCode.BadRequest, outside.StatusCode);
        var checkin = new { qrToken, latitude = 10.7769, longitude = 106.7009, accuracyMeters = 10, motionScore = 0.2 };
        var record = await Success(await employeeClient.PostAsJsonAsync("/api/attendance/check-in", checkin));
        Assert.Equal(worker.Id, record.GetProperty("employeeId").GetGuid());
        Assert.Equal(HttpStatusCode.Conflict, (await employeeClient.PostAsJsonAsync("/api/attendance/check-in", checkin)).StatusCode);
        Assert.Empty((await Success(await otherClient.GetAsync("/api/attendance"))).EnumerateArray());
        Assert.Equal(HttpStatusCode.Forbidden, (await otherClient.GetAsync($"/api/attendance?employeeId={worker.Id}")).StatusCode);
        var saved = await Success(await employeeClient.GetAsync("/api/attendance"));
        Assert.EndsWith("Z", saved[0].GetProperty("checkInAtUtc").GetString());
        var checkout = new { latitude = 10.7769, longitude = 106.7009, accuracyMeters = 10, motionScore = 0.1 };
        Assert.Equal(HttpStatusCode.BadRequest, (await otherClient.PostAsJsonAsync("/api/attendance/check-out", checkout)).StatusCode);
        await Success(await employeeClient.PostAsJsonAsync("/api/attendance/check-out", checkout));
        Assert.Equal(HttpStatusCode.Conflict, (await employeeClient.PostAsJsonAsync("/api/attendance/check-out", checkout)).StatusCode);
        var summary = await Success(await employeeClient.GetAsync("/api/attendance/summary"));
        Assert.Equal("Completed", summary.GetProperty("todayStatus").GetString());
    }

    [Fact]
    public async Task Admin_crud_protects_used_catalogs_and_own_account()
    {
        using var factory = new AttendanceApiFactory();
        await factory.InitializeAsync();
        var admin = await Actor(factory, "admin", Roles.Admin);
        using var client = Client(factory, admin);
        var department = await Success(await client.PostAsJsonAsync("/api/departments", new { name = "Kỹ thuật", description = "Nhóm phát triển" }));
        var departmentId = department.GetProperty("id").GetGuid();
        await Success(await client.PutAsJsonAsync($"/api/departments/{departmentId}", new { name = "Công nghệ", description = "Đã sửa" }));
        var shift = await Success(await client.PostAsJsonAsync("/api/shifts", new { name = "Ca mới", startTime = "08:00", endTime = "17:00", graceMinutes = 5 }));
        var shiftId = shift.GetProperty("id").GetGuid();
        var employee = await Success(await client.PostAsJsonAsync("/api/employees", new { username = "created.user", email = "created@example.test", fullName = "Nhân viên mới", password = "CorrectPassword123!", role = "Employee", departmentId, shiftId }));
        var employeeId = employee.GetProperty("id").GetGuid();
        Assert.False(employee.GetProperty("emailVerified").GetBoolean());
        Assert.Equal(shiftId, employee.GetProperty("shiftId").GetGuid());
        Assert.Equal(HttpStatusCode.Conflict, (await client.DeleteAsync($"/api/departments/{departmentId}")).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await client.DeleteAsync($"/api/shifts/{shiftId}")).StatusCode);
        await Success(await client.PutAsJsonAsync($"/api/employees/{employeeId}", new { fullName = "Tên đã sửa", role = "Employee", departmentId = (Guid?)null, shiftId = (Guid?)null, isActive = true }));
        await Success(await client.DeleteAsync($"/api/departments/{departmentId}"));
        await Success(await client.DeleteAsync($"/api/shifts/{shiftId}"));
        await Success(await client.DeleteAsync($"/api/employees/{employeeId}"));
        Assert.False((await client.DeleteAsync($"/api/employees/{admin.Id}")).IsSuccessStatusCode);
    }

    [Fact]
    public async Task Leaves_enforce_ownership_pending_state_and_supervisor_review_rules()
    {
        using var factory = new AttendanceApiFactory();
        await factory.InitializeAsync();
        var worker = await Actor(factory, "worker", Roles.Employee);
        var manager = await Actor(factory, "manager", Roles.Manager);
        var other = await Actor(factory, "other", Roles.Employee);
        using var workerClient = Client(factory, worker);
        using var managerClient = Client(factory, manager);
        using var otherClient = Client(factory, other);
        var payload = new { type = "Annual", startDate = Rules.Today.AddDays(1), endDate = Rules.Today.AddDays(1), reason = "Nghỉ việc gia đình" };
        var request = await Success(await workerClient.PostAsJsonAsync("/api/leave-requests", payload));
        var id = request.GetProperty("id").GetGuid();
        Assert.Equal(HttpStatusCode.Forbidden, (await otherClient.DeleteAsync($"/api/leave-requests/{id}")).StatusCode);
        await Success(await workerClient.PutAsJsonAsync($"/api/leave-requests/{id}", payload));
        await Success(await managerClient.PatchAsJsonAsync($"/api/leave-requests/{id}/review", new { status = "Approved", reviewNote = "Đồng ý" }));
        Assert.Equal(HttpStatusCode.Conflict, (await workerClient.DeleteAsync($"/api/leave-requests/{id}")).StatusCode);
        var own = await Success(await managerClient.PostAsJsonAsync("/api/leave-requests", payload));
        Assert.Equal(HttpStatusCode.Forbidden, (await managerClient.PatchAsJsonAsync($"/api/leave-requests/{own.GetProperty("id").GetGuid()}/review", new { status = "Approved", reviewNote = "Tự duyệt" })).StatusCode);
        var removable = await Success(await workerClient.PostAsJsonAsync("/api/leave-requests", payload));
        await Success(await workerClient.DeleteAsync($"/api/leave-requests/{removable.GetProperty("id").GetGuid()}"));
    }

    private static async Task<Employee> Actor(AttendanceApiFactory factory, string name, string role)
    {
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AttendanceDbContext>();
        var shift = new Shift { Name = $"Ca {name}", StartTime = new TimeOnly(8, 0), EndTime = new TimeOnly(17, 0), GraceMinutes = 5 };
        var actor = new Employee { Username = name, NormalizedUsername = name.ToUpperInvariant(), Email = $"{name}@example.test", NormalizedEmail = $"{name}@example.test".ToUpperInvariant(), FullName = $"Test {name}", Role = role, EmailVerified = true, Shift = shift, ShiftId = shift.Id };
        db.Employees.Add(actor);
        await db.SaveChangesAsync();
        return actor;
    }

    private static HttpClient Client(AttendanceApiFactory factory, Employee actor)
    {
        var client = factory.CreateClient();
        var token = factory.Services.GetRequiredService<TokenService>().Access(actor).Token;
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return client;
    }

    private static async Task<HttpResponseMessage> AnonymousWithToken(AttendanceApiFactory factory, string token)
    {
        using var client = factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return await client.GetAsync("/api/auth/me");
    }
}
