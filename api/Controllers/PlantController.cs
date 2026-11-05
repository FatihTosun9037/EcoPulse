using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace EcoPulse.Api.Controllers;

[ApiController]
[Authorize]
public sealed class PlantController(PlantEngine plant) : ControllerBase
{
    [HttpGet("/machines")]
    public IReadOnlyList<MachineDto> GetMachines() => plant.Machines();

    [HttpGet("/alarms")]
    public IReadOnlyList<AlarmDto> GetAlarms() => plant.Alarms();

    [Authorize(Roles = "manager")]
    [HttpGet("/dashboard")]
    public DashboardDto GetDashboard() => plant.Dashboard();

    [Authorize(Roles = "manager")]
    [HttpGet("/personnel")]
    public IReadOnlyList<PersonnelDto> GetPersonnel() => plant.Personnel();

    [Authorize(Roles = "manager")]
    [HttpPost("/personnel/{personnelId:int}/assign/{machineId:int}")]
    public ActionResult<AssignmentResultDto> Assign(int personnelId, int machineId)
    {
        AssignmentResultDto result = plant.AssignMachine(personnelId, machineId);
        return result.Saved ? result : NotFound(result);
    }

    [Authorize(Roles = "manager")]
    [HttpPost("/machines/{machineId:int}/unassign")]
    public ActionResult<AssignmentResultDto> Unassign(int machineId)
    {
        AssignmentResultDto result = plant.UnassignMachine(machineId);
        return result.Saved ? result : NotFound(result);
    }

    [Authorize(Roles = "operator,manager")]
    [HttpPost("/machines/{id:int}/fault")]
    public ActionResult<MessageDto> Fault(int id)
    {
        string? message = plant.SetFault(id);
        return message is null ? NotFound() : new MessageDto(message);
    }

    [Authorize(Roles = "operator,manager")]
    [HttpPost("/machines/{id:int}/normal")]
    public ActionResult<MessageDto> Normal(int id)
    {
        string? message = plant.ClearFault(id);
        return message is null ? NotFound() : new MessageDto(message);
    }

    [HttpPost("/devices")]
    public IActionResult RegisterDevice([FromBody] DeviceRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Token))
        {
            return BadRequest();
        }

        plant.RegisterDevice(User.Identity?.Name ?? "", User.FindFirst(ClaimTypes.Role)?.Value ?? "", request.Token);
        return NoContent();
    }

    [HttpDelete("/devices/{token}")]
    public IActionResult RemoveDevice(string token)
    {
        plant.RemoveDevice(token);
        return NoContent();
    }

    [Authorize(Roles = "manager")]
    [HttpGet("/notifications")]
    public IReadOnlyList<NoticeDto> Notifications([FromQuery] string? device) =>
        plant.Notices(User.Identity?.Name ?? "", User.FindFirst(ClaimTypes.Role)?.Value ?? "", device);

    [Authorize(Roles = "manager")]
    [HttpPost("/notifications/{id:int}/ack")]
    public IActionResult Ack(int id, [FromQuery] string? device)
    {
        plant.Ack(User.Identity?.Name ?? "", device, id);
        return NoContent();
    }

    [Authorize(Roles = "operator,manager")]
    [HttpPost("/alarms/{id:int}/maintenance")]
    public ActionResult<MessageDto> Maintenance(int id)
    {
        string? message = plant.ReportMaintenance(id);
        return message is null
            ? Conflict(new MessageDto("Alarm artık aktif değil; bakım doğrulaması başlatılmadı."))
            : new MessageDto(message);
    }
}
