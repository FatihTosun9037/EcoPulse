$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
dotnet run --project .\dashboard\EcoPulse.Dashboard.csproj
