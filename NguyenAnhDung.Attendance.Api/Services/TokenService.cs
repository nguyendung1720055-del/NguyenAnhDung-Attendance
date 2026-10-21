using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Microsoft.IdentityModel.Tokens;
using NguyenAnhDung.Attendance.Api.Models;

namespace NguyenAnhDung.Attendance.Api.Services;

public sealed class TokenService(JwtOptions options)
{
    private readonly byte[] key = Encoding.UTF8.GetBytes(options.Key);
    public TokenValidationParameters AccessValidation() => Validation(options.Audience, key);
    private TokenValidationParameters Validation(string audience, byte[] signingKey) => new()
    {
        ValidateIssuer = true, ValidIssuer = options.Issuer,
        ValidateAudience = true, ValidAudience = audience,
        ValidateLifetime = true, RequireExpirationTime = true, RequireSignedTokens = true,
        ValidateIssuerSigningKey = true, IssuerSigningKey = new SymmetricSecurityKey(signingKey),
        ValidAlgorithms = [SecurityAlgorithms.HmacSha256], ClockSkew = TimeSpan.Zero,
        NameClaimType = "name", RoleClaimType = "role"
    };
    public (string Token, DateTime Expiry) Access(Employee user)
    {
        var expiry = DateTime.UtcNow.AddMinutes(options.LifetimeMinutes);
        var claims = new[] { new Claim("sub", user.Id.ToString()), new Claim("role", user.Role), new Claim("name", user.FullName), new Claim("purpose", "access"), new Claim("jti", Guid.NewGuid().ToString()) };
        return (Create(options.Audience, claims, expiry, key), expiry);
    }
    public (string Token, DateTime Expiry) Qr(int seconds, Guid creator)
    {
        var expiry = DateTime.UtcNow.AddSeconds(seconds);
        var claims = new[] { new Claim("purpose", "attendance-qr"), new Claim("sub", creator.ToString()), new Claim("jti", Guid.NewGuid().ToString()) };
        return (Create("NguyenAnhDung.AttendanceQr", claims, expiry, QrKey()), expiry);
    }
    public void ValidateQr(string token)
    {
        try
        {
            var principal = new JwtSecurityTokenHandler { MapInboundClaims = false }.ValidateToken(token, Validation("NguyenAnhDung.AttendanceQr", QrKey()), out _);
            if (principal.FindFirstValue("purpose") != "attendance-qr") throw new SecurityTokenException();
        }
        catch (Exception ex) when (ex is SecurityTokenException or ArgumentException)
        { throw ApiException.Bad("Mã QR không hợp lệ hoặc đã hết hạn. Hãy quét mã mới từ quản lý."); }
    }
    private byte[] QrKey() => HMACSHA256.HashData(key, Encoding.UTF8.GetBytes("NguyenAnhDung/attendance-qr/v1"));
    public string HashCode(Guid challengeId, string purpose, string code) => Convert.ToHexString(HMACSHA256.HashData(key, Encoding.UTF8.GetBytes($"{challengeId}:{purpose}:{code}")));
    public bool CodeMatches(EmailChallenge challenge, string code)
    {
        var expected = Encoding.UTF8.GetBytes(challenge.CodeHash);
        var actual = Encoding.UTF8.GetBytes(HashCode(challenge.Id, challenge.Purpose, code));
        return CryptographicOperations.FixedTimeEquals(expected, actual);
    }
    private string Create(string audience, IEnumerable<Claim> claims, DateTime expiry, byte[] signingKey)
    {
        var token = new JwtSecurityToken(options.Issuer, audience, claims, DateTime.UtcNow, expiry, new SigningCredentials(new SymmetricSecurityKey(signingKey), SecurityAlgorithms.HmacSha256));
        return new JwtSecurityTokenHandler().WriteToken(token);
    }
}
