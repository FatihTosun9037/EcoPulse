$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$project = Join-Path $root "dashboard\EcoPulse.Dashboard.csproj"
$publishDirectory = Join-Path $root "EcoPulse-Windows-x64"
$archive = Join-Path $root ("EcoPulse-Windows-x64-{0}.zip" -f (Get-Date -Format "yyyyMMdd-HHmmss"))

& dotnet publish $project `
    --configuration Release `
    --runtime win-x64 `
    --self-contained true `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:DebugType=None `
    -p:DebugSymbols=false `
    --output $publishDirectory `
    --nologo
if ($LASTEXITCODE -ne 0) {
    throw "EcoPulse publication failed."
}

$executable = Join-Path $publishDirectory "EcoPulse.Dashboard.exe"
if (-not (Test-Path $executable)) {
    throw "The published EcoPulse executable was not created."
}

Copy-Item -LiteralPath (Join-Path $root "README.txt") -Destination $publishDirectory
Copy-Item -LiteralPath (Join-Path $root "dashboard\ecopulse.ico") -Destination $publishDirectory
Compress-Archive -Path (Join-Path $publishDirectory "*") -DestinationPath $archive
Write-Output "Portable application: $executable"
Write-Output "Shareable package: $archive"
