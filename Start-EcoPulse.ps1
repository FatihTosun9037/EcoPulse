$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$standalone = Join-Path $root "EcoPulse-Windows-x64\EcoPulse.Dashboard.exe"
$development = Join-Path $root "dashboard\bin\Release\net9.0-windows\EcoPulse.Dashboard.exe"

if (Test-Path $standalone) {
    Start-Process -FilePath $standalone
    exit
}

if (Test-Path $development) {
    Start-Process -FilePath $development
    exit
}

Add-Type -AssemblyName PresentationFramework
[System.Windows.MessageBox]::Show(
    "EcoPulse yayımlanmamış. Önce Publish-EcoPulse.ps1 dosyasını çalıştırın.",
    "EcoPulse başlatılamadı",
    [System.Windows.MessageBoxButton]::OK,
    [System.Windows.MessageBoxImage]::Error
) | Out-Null
