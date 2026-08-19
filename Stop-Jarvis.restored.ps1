param(
    [int]$Port = 8765,
    [switch]$Silent
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ProjectRoot "Jarvis-Runtime.ps1")
$Paths = Get-JarvisRuntimePaths -ProjectRoot $ProjectRoot -Port $Port

function Show-JarvisMessage {
    param([string]$Message)
    if ($Silent) { Write-Host $Message; return }
    try {
        $shell = New-Object -ComObject WScript.Shell
        [void]$shell.Popup($Message, 8, "Jarvis", 64)
    }
    catch { Write-Host $Message }
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
    if (-not $listenerPid) {
        Remove-JarvisStaleRuntimeFiles -Paths $Paths
        Show-JarvisMessage "Jarvis ya estaba detenido."
        return
    }

    $health = Invoke-JarvisHealthCheck -Port $Port -TimeoutMilliseconds 1200
    $metadata = Get-JarvisInstanceMetadata -InstanceFile $Paths.InstanceFile
    $ownership = Test-JarvisOwnedListener -ProjectRoot $ProjectRoot -Port $Port -ListenerPid $listenerPid -Health $health -Metadata $metadata
    if (-not $ownership.Owned) {
        Show-JarvisMessage "El proceso PID $listenerPid que usa el puerto $Port no pudo validarse como este Jarvis. No se detuvo ningun proceso."
        return
    }

    Stop-Process -Id $listenerPid -Force
    for ($attempt = 0; $attempt -lt 24; $attempt++) {
        Start-Sleep -Milliseconds 250
        if (-not (Get-JarvisListenerPid -Port $Port)) {
            Remove-JarvisStaleRuntimeFiles -Paths $Paths
            Show-JarvisMessage "Jarvis fue detenido de forma segura."
            return
        }
    }
    Show-JarvisMessage "Se envio la orden de detencion a Jarvis PID $listenerPid, pero el puerto $Port sigue ocupado. No se modifico ningun otro proceso."
}
finally {
    try { $mutex.ReleaseMutex() } catch {}
    $mutex.Dispose()
}
