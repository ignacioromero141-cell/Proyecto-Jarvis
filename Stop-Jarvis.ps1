param(
    [int]$Port = 8765,
    [switch]$Silent
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RuntimeDir = Join-Path $ProjectRoot "data\runtime"

function Get-JarvisPidFile {
    if ($Port -eq 8765) {
        return (Join-Path $RuntimeDir "jarvis-web.pid")
    }
    return (Join-Path $RuntimeDir "jarvis-web-$Port.pid")
}

$PidFile = Get-JarvisPidFile

function Show-JarvisMessage {
    param([string]$Message)
    if ($Silent) {
        Write-Host $Message
        return
    }
    try {
        $shell = New-Object -ComObject WScript.Shell
        [void]$shell.Popup($Message, 6, "Jarvis", 64)
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

if (-not (Test-Path -LiteralPath $PidFile)) {
    if (-not (Test-JarvisServer)) {
        Show-JarvisMessage "Jarvis ya estaba detenido."
        return
    }

    $listenerPid = Get-JarvisListenerPid
    if (-not $listenerPid) {
        Show-JarvisMessage "Jarvis esta activo, pero no se pudo identificar el proceso para detenerlo."
        return
    }
    $listenerPid | Set-Content -LiteralPath $PidFile -Encoding ASCII
    $pidText = "$listenerPid"
}
else {
    $pidText = (Get-Content -LiteralPath $PidFile -Raw).Trim()
}

if (-not ($pidText -match "^\d+$")) {
    Remove-Item -LiteralPath $PidFile -Force
    Show-JarvisMessage "El archivo de estado de Jarvis estaba danado y fue limpiado."
    return
}

$listenerPid = Get-JarvisListenerPid
if ($listenerPid -and [int]$listenerPid -ne [int]$pidText) {
    $pidText = "$listenerPid"
    $pidText | Set-Content -LiteralPath $PidFile -Encoding ASCII
}
elseif (-not $listenerPid -and -not (Test-JarvisServer)) {
    Remove-Item -LiteralPath $PidFile -Force
    Show-JarvisMessage "Jarvis ya estaba detenido."
    return
}

$process = Get-Process -Id ([int]$pidText) -ErrorAction SilentlyContinue
if (-not $process) {
    Remove-Item -LiteralPath $PidFile -Force
    if (Test-JarvisServer) {
        Show-JarvisMessage "Jarvis esta activo, pero el proceso registrado ya no existe."
    }
    else {
        Show-JarvisMessage "Jarvis ya estaba detenido."
    }
    return
}

Stop-Process -Id $process.Id -Force
for ($attempt = 0; $attempt -lt 20; $attempt++) {
    Start-Sleep -Milliseconds 250
    if (-not (Test-JarvisServer)) {
        Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
        Show-JarvisMessage "Jarvis fue detenido."
        return
    }
}

Show-JarvisMessage "Se intento detener Jarvis, pero el servidor todavia responde en el puerto $Port."
