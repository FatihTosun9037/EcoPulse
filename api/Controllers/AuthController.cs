using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.IdentityModel.Tokens;

namespace EcoPulse.Api.Controllers;

[ApiController]
[Route("auth")]
public sealed class AuthController(IConfiguration configuration) : ControllerBase
{
    private static readonly DemoUser[] Users =
    [
        new("operator", "operator", "operator", "Saha Teknisyeni"),
        new("manager", "manager", "manager", "Tesis Yöneticisi")
    ];

    [AllowAnonymous]
    [HttpPost("login")]
    public ActionResult<LoginResponse> Login([FromBody] LoginRequest request)
    {
        DemoUser? user = Users.FirstOrDefault(candidate =>
            string.Equals(candidate.Username, request.Username.Trim(), StringComparison.Ordinal)
            && string.Equals(candidate.Password, request.Password, StringComparison.Ordinal));
        if (user is null)
        {
            return Unauthorized();
        }

        string key = configuration["Jwt:Key"] ?? throw new InvalidOperationException("Jwt:Key eksik.");
        int minutes = int.TryParse(configuration["Jwt:Minutes"], out int parsed) ? parsed : 720;
        var claims = new[]
        {
            new Claim(ClaimTypes.Name, user.Username),
            new Claim(ClaimTypes.Role, user.Role),
            new Claim("display_name", user.DisplayName)
        };
        var token = new JwtSecurityToken(
            issuer: configuration["Jwt:Issuer"],
            audience: configuration["Jwt:Audience"],
            claims: claims,
            expires: DateTime.UtcNow.AddMinutes(minutes),
            signingCredentials: new SigningCredentials(
                new SymmetricSecurityKey(Encoding.UTF8.GetBytes(key)),
                SecurityAlgorithms.HmacSha256));

        return new LoginResponse(
            new JwtSecurityTokenHandler().WriteToken(token),
            user.Role,
            user.DisplayName);
    }

    [Authorize]
    [HttpGet("me")]
    public ActionResult<MeResponse> Me()
    {
        return new MeResponse(
            User.Identity?.Name ?? "",
            User.FindFirst(ClaimTypes.Role)?.Value ?? "",
            User.FindFirst("display_name")?.Value ?? "");
    }

    public sealed record LoginRequest(string Username, string Password);

    public sealed record LoginResponse(string AccessToken, string Role, string DisplayName);

    public sealed record MeResponse(string Username, string Role, string DisplayName);

    private sealed record DemoUser(string Username, string Password, string Role, string DisplayName);
}
