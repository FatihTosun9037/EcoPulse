# EcoPulse tek başlatma betiği.
# Masaüstü kısayolu bunu çalıştırır: gerekirse derler, API + Flutter penceresini açar.
# Telefon USB ile bağlıysa uygulamayı yükler ve 5080 portunu bilgisayardaki API'ye yönlendirir.

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
# dotnet ve flutter çıktısı UTF-8; log dosyasında Türkçe karakterler bozulmasın.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$logPath = Join-Path $env:LOCALAPPDATA "EcoPulse\start-log.txt"
New-Item -ItemType Directory -Force -Path (Split-Path $logPath) | Out-Null

function Write-Log([string]$message) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $message"
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
}

# Aynı anda tek başlatma: kısayola iki kez tıklanırsa ikinci çağrı derlemeleri çakıştırmasın.
$startMutex = New-Object System.Threading.Mutex($false, "Local\EcoPulseStart")
try {
    $ownsMutex = $startMutex.WaitOne(0)
}
catch [System.Threading.AbandonedMutexException] {
    $ownsMutex = $true
}
if (-not $ownsMutex) {
    Write-Log "Başka bir başlatma zaten sürüyor; bu çağrı atlandı."
    exit 0
}

# Harici komutu çalıştırır, tüm çıktısını log dosyasına yazar ve başarısızsa
# son satırları kullanıcıya gösterilecek hata mesajına ekler.
function Invoke-Logged([string]$label, [scriptblock]$command) {
    Write-Log "$label basliyor."
    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = @(& $command 2>&1 | ForEach-Object { "$_" })
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previous
    }

    if ($output.Count -gt 0) {
        Add-Content -LiteralPath $logPath -Value ($output | ForEach-Object { "    $_" }) -Encoding UTF8
    }

    if ($code -ne 0) {
        $errors = @($output | Where-Object { $_ -match "error|hata|exception" } | Select-Object -Last 3)
        $detail = if ($errors.Count -gt 0) { "`n" + ($errors -join "`n") } else { "" }
        throw "$label basarisiz (cikis kodu $code).$detail"
    }

    Write-Log "$label tamam."
}

# Yalnızca bu klasörden çalışan EcoPulse süreçlerini kapatır. Derleme sırasında
# çalışan exe dosyası kilitli kalır ve 'dotnet build' / 'flutter build' kopyalama adımında düşer.
function Stop-ProjectProcess([string]$name, [datetime]$olderThan = [datetime]::MaxValue) {
    $processes = @(Get-Process -Name $name -ErrorAction SilentlyContinue | Where-Object {
        try {
            $_.Path -and $_.Path.StartsWith($PSScriptRoot, [StringComparison]::OrdinalIgnoreCase) -and $_.StartTime -lt $olderThan
        }
        catch {
            $false
        }
    })
    if ($processes.Count -eq 0) {
        return
    }

    Write-Log "$name kapatiliyor ($($processes.Count) surec)."
    $processes | Stop-Process -Force -ErrorAction SilentlyContinue
    $processes | Wait-Process -Timeout 10 -ErrorAction SilentlyContinue
}

function Set-DesktopShortcut {
    $desktop = [Environment]::GetFolderPath("Desktop")
    $shortcutPath = Join-Path $desktop "EcoPulse.lnk"
    $iconPath = Join-Path $PSScriptRoot "app\assets\brand\ecopulse.ico"
    if (-not (Test-Path -LiteralPath $iconPath)) {
        throw "Kısayol simgesi bulunamadı: $iconPath"
    }

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = Join-Path $PSHOME "powershell.exe"
    $shortcut.Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`""
    $shortcut.WorkingDirectory = $PSScriptRoot
    $shortcut.Description = "EcoPulse'u başlatır ve bağlı Android telefonla eşler."
    $shortcut.IconLocation = "$iconPath,0"
    $shortcut.Save()
}

function Test-BuildRequired([string]$outputPath, [System.IO.FileInfo[]]$sourceFiles) {
    if (-not (Test-Path -LiteralPath $outputPath)) {
        return $true
    }

    $outputTime = (Get-Item -LiteralPath $outputPath).LastWriteTimeUtc
    $latestSource = $sourceFiles | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    return $null -ne $latestSource -and $latestSource.LastWriteTimeUtc -gt $outputTime
}

function Get-AdbSerials([string]$adb) {
    & $adb devices | ForEach-Object {
        if ($_ -match "^(\S+)\s+device$") {
            $Matches[1]
        }
    }
}

function Wait-ForApi {
    for ($attempt = 0; $attempt -lt 40; $attempt++) {
        $request = [System.Net.HttpWebRequest]::Create("http://127.0.0.1:5080/health")
        $request.Method = "GET"
        $request.Timeout = 1000
        try {
            $response = $request.GetResponse()
            $healthy = [int]$response.StatusCode -eq 200
            $response.Dispose()
            if ($healthy) {
                return $true
            }
        }
        catch [System.Net.WebException] {
        }

        Start-Sleep -Milliseconds 250
    }

    return $false
}

function Connect-Phone([string]$adb, [string]$apk) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        foreach ($serial in @(Get-AdbSerials $adb)) {
            & $adb -s $serial reverse tcp:5080 tcp:5080 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Log "Telefon tüneli kurulamadı: $serial"
                continue
            }

            Write-Log "Telefon API tüneli hazır: $serial"
            $install = @(& $adb -s $serial install -r $apk 2>&1 | ForEach-Object { "$_" })
            if ($LASTEXITCODE -ne 0) {
                Write-Log "EcoPulse telefona yüklenemedi: $serial  $($install -join ' ')"
                continue
            }

            & $adb -s $serial shell am start -n "com.ecopulse.ecopulse/.MainActivity" | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Log "EcoPulse telefonda açıldı: $serial"
            }
            else {
                Write-Log "EcoPulse telefonda açılamadı: $serial"
            }
        }
    }
    catch {
        Write-Log "Telefon bağlantısı atlandı: $($_.Exception.Message)"
    }
    finally {
        $ErrorActionPreference = $previous
    }
}

try {
    Write-Log "Start-EcoPulse basladi."
    Set-DesktopShortcut

    $launcher = Join-Path $PSScriptRoot "launcher\bin\Debug\net9.0-windows\EcoPulse.Launcher.exe"
    $api = Join-Path $PSScriptRoot "api\bin\Debug\net9.0\EcoPulse.Api.exe"
    $desktopApp = Join-Path $PSScriptRoot "app\build\windows\x64\runner\Release\ecopulse.exe"
    $phoneApk = Join-Path $PSScriptRoot "app\build\app\outputs\flutter-apk\app-release.apk"
    $adb = "C:\Android\platform-tools\adb.exe"
    $apiSources = @(
        Get-ChildItem .\api -File
        Get-ChildItem .\api\Controllers -File
        Get-ChildItem .\api\Properties -File
    )
    $launcherSources = @(Get-ChildItem .\launcher -File)
    $flutterSources = @(
        Get-ChildItem .\app\lib -File -Recurse
        Get-ChildItem .\app\assets -File -Recurse
        Get-ChildItem .\app\windows\runner -File -Recurse
        Get-Item .\app\pubspec.yaml
    )
    $phoneSources = @(
        Get-ChildItem .\app\lib -File -Recurse
        Get-ChildItem .\app\assets -File -Recurse
        Get-ChildItem .\app\android\app\src -File -Recurse
        Get-Item .\app\pubspec.yaml
        Get-Item .\app\pubspec.lock
        Get-Item .\app\android\app\build.gradle.kts
        Get-Item .\app\android\build.gradle.kts
        Get-Item .\app\android\settings.gradle.kts
        Get-Item .\app\android\gradle.properties
    )

    if (Test-BuildRequired $api $apiSources) {
        Stop-ProjectProcess "EcoPulse.Api"
        Invoke-Logged "API derlemesi" { dotnet build .\api\EcoPulse.Api.csproj --nologo -v minimal }
    }

    if (Test-BuildRequired $launcher $launcherSources) {
        Stop-ProjectProcess "EcoPulse.Launcher"
        Invoke-Logged "Launcher derlemesi" { dotnet build .\launcher\EcoPulse.Launcher.csproj --nologo -v minimal }
    }

    # --no-tree-shake-icons: artımlı derlemede yeni eklenen ikonların kırpılmış fonttan düşmesini önler.
    if (Test-BuildRequired $desktopApp $flutterSources) {
        Stop-ProjectProcess "ecopulse"
        Push-Location .\app
        try {
            Invoke-Logged "Flutter Windows derlemesi" { flutter build windows --release --no-tree-shake-icons }
        }
        finally {
            Pop-Location
        }
    }

    # Masaüstü uygulaması Android derlemesini beklemeden açılır; telefon adımı arkadan gelir.
    # Derlenmiş API'den daha eski bir API süreci açık kalmışsa (önceki oturumdan) yenisiyle değiştir.
    if (Test-Path -LiteralPath $api) {
        Stop-ProjectProcess "EcoPulse.Api" (Get-Item -LiteralPath $api).LastWriteTime
    }

    if (-not (Test-Path -LiteralPath $launcher)) {
        throw "Launcher bulunamadı: $launcher"
    }

    Write-Log "Launcher açılıyor."
    Start-Process -FilePath $launcher -WorkingDirectory (Split-Path $launcher)
    if (-not (Wait-ForApi)) {
        throw "Yerel API başlatılamadı. 5080 portunu başka bir uygulama kullanıyor olabilir."
    }

    Write-Log "API hazır: http://127.0.0.1:5080"

    $phoneConnected = (Test-Path -LiteralPath $adb) -and (@(Get-AdbSerials $adb).Count -gt 0)
    if (-not (Test-Path -LiteralPath $adb)) {
        Write-Log "adb bulunamadı; telefon adımı atlandı."
    }
    elseif (-not $phoneConnected) {
        Write-Log "USB ile bağlı telefon yok; telefon adımı atlandı."
    }

    if ($phoneConnected -and (Test-BuildRequired $phoneApk $phoneSources)) {
        Push-Location .\app
        try {
            Invoke-Logged "Android derlemesi" { flutter build apk --release --no-tree-shake-icons }
        }
        finally {
            Pop-Location
        }
    }

    if ($phoneConnected) {
        Connect-Phone $adb $phoneApk
    }

    Write-Log "Start-EcoPulse tamam."
}
catch {
    Write-Log "HATA: $($_.Exception.Message)"
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        "EcoPulse açılamadı.`n$($_.Exception.Message)`n`nAyrıntı: $logPath",
        "EcoPulse",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    exit 1
}
