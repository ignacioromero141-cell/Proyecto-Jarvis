param(
    [Parameter(Mandatory)][string]$ServerScript,
    [Parameter(Mandatory)][string]$ProjectRoot,
    [Parameter(Mandatory)][int]$Port
)
$ErrorActionPreference = "Stop"
. $ServerScript
Start-JarvisWebServer -ProjectRoot $ProjectRoot -Port $Port -Quiet
