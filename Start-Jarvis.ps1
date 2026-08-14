param(
    [int]$Port = 8765,
    [switch]$NoBrowser
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RuntimeDir = Join-Path $ProjectRoot "data\runtime"
$Url = "http://localhost:$Port"

function Get-JarvisPidFile {
    if ($Port -eq 8765) {
        return (Join-Path $RuntimeDir "jarvis-web.pid")
    }
    return (Join-Path $RuntimeDir "jarvis-web-$Port.pid")
}

$PidFile = Get-JarvisPidFile

function Show-JarvisMessage {
    param([string]$Message)
    try {
        $shell = New-Object -ComObject WScript.Shell
        [void]$shell.Popup($Message, 8, "Jarvis", 64)
    }
    catch {
        Write-Host $Message
    }
}

function Test-JarvisServer {
    $client = $null
    try {
        $client = [System.Net.Sockets.TcpClient]::new()
        $connect = $client.BeginConnect("127.0.0.1", $Port, $null, $null)
        if (-not $connect.AsyncWaitHandle.WaitOne(300)) {
            return $false
        }
        $client.EndConnect($connect)
        $client.ReceiveTimeout = 700
        $client.SendTimeout = 700
        $stream = $client.GetStream()
        $requestBytes = [System.Text.Encoding]::ASCII.GetBytes("GET /api/sync/status HTTP/1.1`r`nHost: 127.0.0.1`r`nConnection: close`r`n`r`n")
        $stream.Write($requestBytes, 0, $requestBytes.Length)
        $buffer = New-Object byte[] 256
        $read = $stream.Read($buffer, 0, $buffer.Length)
        if ($read -le 0) {
            return $false
        }
        $responseText = [System.Text.Encoding]::ASCII.GetString($buffer, 0, $read)
        return $responseText.StartsWith("HTTP/1.1 200")
    }
    catch {
        return $false
    }
    finally {
        if ($null -ne $client) {
            $client.Close()
        }
    }
}

function Get-JarvisListenerPid {
    try {
        $connection = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($connection -and $connection.OwningProcess) {
            return [int]$connection.OwningProcess
        }
    }
    catch {}

    try {
        $lines = @(netstat -ano -p tcp 2>$null | Select-String "LISTENING")
        foreach ($line in $lines) {
            $text = ($line.Line -replace "\s+", " ").Trim()
            $parts = $text.Split(" ")
            if ($parts.Count -ge 5 -and $parts[1] -match ":$Port$") {
                return [int]$parts[4]
            }
        }
    }
    catch {}

    return $null
}

if (-not (Test-Path -LiteralPath $RuntimeDir)) {
    New-Item -ItemType Directory -Path $RuntimeDir | Out-Null
}

if (Test-JarvisServer) {
    $listenerPid = Get-JarvisListenerPid
    if ($listenerPid) {
        $listenerPid | Set-Content -LiteralPath $PidFile -Encoding ASCII
    }
    if (-not $NoBrowser) {
        Start-Process $Url
    }
    return
}

if (Test-Path -LiteralPath $PidFile) {
    Remove-Item -LiteralPath $PidFile -Force
}

$scriptPath = Join-Path $ProjectRoot "jarvis-web.ps1"
$powerShellPath = (Get-Command powershell.exe).Source
$processInfo = [System.Diagnostics.ProcessStartInfo]::new()
$processInfo.FileName = $powerShellPath
$processInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -Port $Port -Quiet"
$processInfo.WorkingDirectory = $ProjectRoot
$processInfo.UseShellExecute = $true
$processInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden

$process = [System.Diagnostics.Process]::Start($processInfo)

$process.Id | Set-Content -LiteralPath $PidFile -Encoding ASCII

for ($attempt = 0; $attempt -lt 20; $attempt++) {
    Start-Sleep -Milliseconds 500
    if (Test-JarvisServer) {
        if (-not $NoBrowser) {
            Start-Process $Url
        }
        return
    }
    if ($process.HasExited) {
        Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
        Show-JarvisMessage "No se pudo iniciar Jarvis en el puerto $Port. El proceso se cerro antes de aceptar conexiones."
        return
    }
}

if (-not $process.HasExited) {
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
}
Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
Show-JarvisMessage "No se pudo iniciar Jarvis en el puerto $Port. Revisa si otra app esta usando el puerto o si Windows bloqueo el acceso de red."
