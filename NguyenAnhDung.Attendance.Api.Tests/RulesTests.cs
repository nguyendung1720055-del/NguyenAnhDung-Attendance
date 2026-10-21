using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Microsoft.IdentityModel.Tokens;
using NguyenAnhDung.Attendance.Api.Models;
using NguyenAnhDung.Attendance.Api.Services;
using Xunit;

namespace NguyenAnhDung.Attendance.Api.Tests;

public class RulesTests
{
    private const string SigningKey = "Tests-only-signing-key-must-never-be-used-in-production-123456789!";
    private static TokenService Tokens() => new(new JwtOptions {
        Key = SigningKey,
        Issuer = "NguyenAnhDung.Attendance.Api", Audience = "NguyenAnhDung.Attendance.Mobile"
    });

    [Theory]
    [InlineData("shortA1")]
    [InlineData("onlylowercase123")]
    [InlineData("ONLYUPPERCASE123")]
    [InlineData("NoDigitsInThisPassword")]
    public void Password_rejects_missing_requirements(string password) =>
        Assert.Equal(400, Assert.Throws<ApiException>(() => Rules.Password(password)).Status);

    [Fact]
    public void Geofence_accepts_office_but_rejects_outside_and_poor_accuracy()
    {
        var office = new CompanySettings { Latitude = 10.7769, Longitude = 106.7009, RadiusMeters = 150, MaxAccuracyMeters = 50 };
        Rules.Location(office, office.Latitude, office.Longitude, 10, 0);
        Assert.Throws<ApiException>(() => Rules.Location(office, 10.7869, office.Longitude, 10, 0));
        Assert.Throws<ApiException>(() => Rules.Location(office, office.Latitude, office.Longitude, 51, 0));
        Assert.Throws<ApiException>(() => Rules.Location(office, double.NaN, office.Longitude, 10, 0));
        Assert.Throws<ApiException>(() => Rules.Location(office, office.Latitude, office.Longitude, 10, double.PositiveInfinity));
    }

    [Fact]
    public void Haversine_handles_same_point_and_antipodes()
    {
        Assert.Equal(0, Rules.DistanceMeters(10, 20, 10, 20), 6);
        Assert.InRange(Rules.DistanceMeters(0, 0, 0, 180), 20_000_000, 20_020_000);
    }

    [Theory]
    [InlineData("22:00", "06:00")]
    [InlineData("09:00", "09:00")]
    [InlineData("25:00", "26:00")]
    public void Shift_rejects_overnight_or_invalid_times(string start, string end) =>
        Assert.Throws<ApiException>(() => Rules.ShiftTimes(new ShiftInput("Ca test", start, end, 5)));

    [Fact]
    public void Correction_must_reference_a_single_past_day()
    {
        var yesterday = Rules.Today.AddDays(-1);
        Rules.Leave(new LeaveInput("Correction", yesterday, yesterday, "Quên chấm công ra"));
        Assert.Throws<ApiException>(() => Rules.Leave(new LeaveInput("Correction", Rules.Today, Rules.Today, "Quên chấm công ra")));
        Assert.Throws<ApiException>(() => Rules.Leave(new LeaveInput("Correction", yesterday.AddDays(-1), yesterday, "Quên chấm công ra")));
    }

    [Fact]
    public void Qr_token_cannot_be_used_as_access_token_and_access_cannot_be_qr()
    {
        var tokens = Tokens();
        var employee = new Employee { FullName = "Nhân viên test" };
        var qr = tokens.Qr(60, employee.Id).Token;
        tokens.ValidateQr(qr);
        var access = tokens.Access(employee).Token;
        Assert.Throws<ApiException>(() => tokens.ValidateQr(access));
        Assert.ThrowsAny<SecurityTokenException>(() => new JwtSecurityTokenHandler().ValidateToken(qr, tokens.AccessValidation(), out _));
        var tampered = qr[..^8] + "AAAAAAAA";
        Assert.Throws<ApiException>(() => tokens.ValidateQr(tampered));
    }

    [Fact]
    public void Qr_expiry_is_enforced_without_clock_skew()
    {
        var tokens = Tokens();
        var qrKey = HMACSHA256.HashData(Encoding.UTF8.GetBytes(SigningKey), Encoding.UTF8.GetBytes("NguyenAnhDung/attendance-qr/v1"));
        var expired = new JwtSecurityTokenHandler().WriteToken(new JwtSecurityToken(
            "NguyenAnhDung.Attendance.Api", "NguyenAnhDung.AttendanceQr", [new Claim("purpose", "attendance-qr")],
            DateTime.UtcNow.AddMinutes(-2), DateTime.UtcNow.AddSeconds(-1),
            new SigningCredentials(new SymmetricSecurityKey(qrKey), SecurityAlgorithms.HmacSha256)));
        Assert.Throws<ApiException>(() => tokens.ValidateQr(expired));
    }

    [Fact]
    public void Otp_hash_is_bound_to_challenge_and_purpose()
    {
        var tokens = Tokens();
        var challenge = new EmailChallenge { Purpose = "LoginOtp" };
        challenge.CodeHash = tokens.HashCode(challenge.Id, challenge.Purpose, "012345");
        Assert.True(tokens.CodeMatches(challenge, "012345"));
        Assert.False(tokens.CodeMatches(challenge, "999999"));
        challenge.Id = Guid.NewGuid();
        Assert.False(tokens.CodeMatches(challenge, "012345"));
        challenge.Id = Guid.NewGuid();
        Assert.NotEqual(tokens.HashCode(challenge.Id, "LoginOtp", "012345"), tokens.HashCode(challenge.Id, "VerifyEmail", "012345"));
    }
}
