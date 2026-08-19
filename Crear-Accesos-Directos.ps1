[CmdletBinding()]
param(
    [string]$DesktopPath = [Environment]::GetFolderPath("Desktop")
)

$ErrorActionPreference = "Stop"
$projectRoot = [IO.Path]::GetFullPath($PSScriptRoot)
$desktop = [IO.Path]::GetFullPath($DesktopPath)
$powerShell = (Get-Command powershell.exe -ErrorAction Stop).Source
$startScript = Join-Path $projectRoot "Start-Jarvis.ps1"
$stopScript = Join-Path $projectRoot "Detener-Jarvis.ps1"

foreach ($required in @($startScript, $stopScript)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Falta el script requerido: $required"
    }
}
if (-not (Test-Path -LiteralPath $desktop -PathType Container)) {
    throw "No existe el escritorio indicado: $desktop"
}

$shell = New-Object -ComObject WScript.Shell
foreach ($definition in @(
    [pscustomobject]@{ Name = "Iniciar Jarvis.lnk"; Script = $startScript },
    [pscustomobject]@{ Name = "Detener Jarvis.lnk"; Script = $stopScript }
)) {
    $shortcutPath = Join-Path $desktop $definition.Name
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $powerShell
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$($definition.Script)`""
    $shortcut.WorkingDirectory = $projectRoot
    $shortcut.Description = $definition.Name.Replace(".lnk", "")
    $shortcut.Save()
    Write-Host "Acceso directo actualizado: $shortcutPath"
}
