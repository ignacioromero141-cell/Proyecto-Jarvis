param(
    [int]$Port = 8765,
    [switch]$SmokeTest
)

$ErrorActionPreference = "Stop"

# Este archivo queda como lanzador simple.
# La implementacion real vive en src/web/server.ps1 para que el proyecto crezca por modulos.
. (Join-Path $PSScriptRoot "src\web\server.ps1")

Start-JarvisWebServer -ProjectRoot $PSScriptRoot -Port $Port -SmokeTest:$SmokeTest
