param(
    [int]$Port = 8765,
    [switch]$NoBrowser,
    [switch]$PassThru
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ProjectRoot "Jarvis-Runtime.ps1")

$Url = "http://localhost:$Port"
$Paths = Get-JarvisRuntimePaths -ProjectRoot $ProjectRoot -Port $Port

function Show-JarvisMessage {
    param([string]$Message)
    if ($NoBrowser) { Write-Host $Message; return }
    try {
        $shell = New-Object -ComObject WScript.Shell
        [void]$shell.Popup($Message, 10, "Jarvis", 64)
    }
    catch { Write-Host $Message }
}

if (-not (Test-Path -LiteralPath $Paths.RuntimeDirectory)) {
    New-Item -ItemType Directory -Path $Paths.RuntimeDirectory | Out-Null
}

$createdNew = $false
$mutex = [System.Threading.Mutex]::new($true, (Get-JarvisStartMutexName -ProjectRoot $ProjectRoot -Port $Port), [ref]$createdNew)
if (-not $createdNew) {
    $mutex.Dispose()
    Show-JarvisMessage "Jarvis ya esta procesando otra orden de inicio o detencion. Espera unos segundos y volve a intentar."
    return
}

try {
    $listenerPid = Get-JarvisListenerPid -Port $Port
    if ($listenerPid) {
        $health = Invoke-JarvisHealthCheck -Port $Port -TimeoutMilliseconds 1200
        $metadata = Get-JarvisInstanceMetadata -InstanceFile $Paths.InstanceFile
        $ownership = Test-JarvisOwnedListener -ProjectRoot $ProjectRoot -Port $Port -ListenerPid $listenerPid -Health $health -Metadata $metadata

        if ($health -and $ownership.Owned) {
            if (-not $NoBrowser) { Start-Process $Url }
            return
        }
        if ($ownership.Owned) {
            Show-JarvisMessage "Jarvis esta activo en el puerto $Port (PID $listenerPid), pero no responde. No se inicio otra copia. Usa 'Detener-Jarvis.vbs' y luego volve a iniciar para recuperarlo de forma segura."
            return
        }
        Show-JarvisMessage "El puerto $Port esta ocupado por otro proceso (PID $listenerPid). Jarvis no lo modifico ni intento iniciar otra instancia."
        return
    }

    Remove-JarvisStaleRuntimeFiles -Paths $Paths
    $scriptPath = Join-Path $ProjectRoot "jarvis-web.ps1"
    $powerShellPath = (Get-Command powershell.exe).Source
    $arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$scriptPath`"", "-Port", "$Port", "-Quiet")
    $process = Start-Process -FilePath $powerShellPath -ArgumentList $arguments -WorkingDirectory $ProjectRoot -WindowStyle Hidden -PassThru

    for ($attempt = 0; $attempt -lt 24; $attempt++) {
        Start-Sleep -Milliseconds 250
        $health = Invoke-JarvisHealthCheck -Port $Port -TimeoutMilliseconds 500
        if ($health -and $health.service -eq "jarvis-web" -and [int]$health.pid -eq $process.Id) {
            if (-not $NoBrowser) { Start-Process $Url }
            if ($PassThru) { return $process }
            return
        }
        if ($process.HasExited) {
            Show-JarvisMessage "No se pudo iniciar Jarvis en el puerto $Port. El proceso termino con codigo $($process.ExitCode)."
            return
        }
    }

    Show-JarvisMessage "Jarvis se inicio con PID $($process.Id), pero no alcanzo a responder dentro de 6 segundos. No se detuvo automaticamente: usa 'Detener-Jarvis.vbs' si necesitas recuperarlo."
}
finally {
    try { $mutex.ReleaseMutex() } catch {}
    $mutex.Dispose()
}
