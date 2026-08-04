param(
    [string[]]$Command
)

$ErrorActionPreference = "Stop"
$dataDirectory = Join-Path $PSScriptRoot "data"
$dataFile = Join-Path $dataDirectory "records.json"

function Initialize-Storage {
    if (-not (Test-Path -LiteralPath $dataDirectory)) {
        New-Item -ItemType Directory -Path $dataDirectory | Out-Null
    }

    if (-not (Test-Path -LiteralPath $dataFile)) {
        "[]" | Set-Content -LiteralPath $dataFile -Encoding UTF8
    }
}

function Read-Records {
    $content = Get-Content -LiteralPath $dataFile -Raw
    if ([string]::IsNullOrWhiteSpace($content)) {
        return @()
    }

    $records = ConvertFrom-Json -InputObject $content
    return @($records | ForEach-Object { $_ })
}

function Write-Records {
    param([array]$Records)

    ConvertTo-Json -InputObject $Records -Depth 4 |
        Set-Content -LiteralPath $dataFile -Encoding UTF8
}

function Get-ShortId {
    return ([guid]::NewGuid().ToString("N").Substring(0, 6))
}

function Add-Record {
    param(
        [string]$Type,
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        Write-Host "Falta escribir el contenido." -ForegroundColor Yellow
        return
    }

    $records = @(Read-Records)
    $record = [pscustomobject]@{
        id = Get-ShortId
        type = $Type
        text = $Text.Trim()
        status = if ($Type -eq "tarea") { "pendiente" } else { "activo" }
        created_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
        updated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    }

    $records += $record
    Write-Records -Records $records
    Write-Host "Guardado [$($record.id)]: $($record.text)" -ForegroundColor Green
}

function Show-Records {
    param([string]$Type)

    $records = @(Read-Records | Where-Object {
        $_.type -eq $Type -and ($Type -ne "tarea" -or $_.status -eq "pendiente")
    })

    if ($records.Count -eq 0) {
        Write-Host "Todavia no hay registros de tipo '$Type'." -ForegroundColor DarkGray
        return
    }

    foreach ($record in $records) {
        $status = if ($Type -eq "tarea") { " [$($record.status)]" } else { "" }
        Write-Host "[$($record.id)]$status $($record.text)"
    }
}

function Complete-Task {
    param([string]$Id)

    $records = @(Read-Records)
    $record = $records | Where-Object { $_.id -eq $Id -and $_.type -eq "tarea" } | Select-Object -First 1

    if (-not $record) {
        Write-Host "No encontre una tarea con el codigo '$Id'." -ForegroundColor Yellow
        return
    }

    $record.status = "completada"
    $record.updated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    Write-Records -Records $records
    Write-Host "Tarea completada: $($record.text)" -ForegroundColor Green
}

function Remove-Record {
    param([string]$Id)

    $records = @(Read-Records)
    $remainingRecords = @($records | Where-Object { $_.id -ne $Id })

    if ($remainingRecords.Count -eq $records.Count) {
        Write-Host "No encontre un registro con el codigo '$Id'." -ForegroundColor Yellow
        return
    }

    Write-Records -Records $remainingRecords
    Write-Host "Registro eliminado." -ForegroundColor Green
}

function Show-Help {
    Write-Host ""
    Write-Host "Comandos disponibles" -ForegroundColor Cyan
    Write-Host "  idea <texto>       Guardar una idea"
    Write-Host "  tarea <texto>      Agregar una tarea"
    Write-Host "  recorda <texto>    Guardar un recuerdo autorizado por vos"
    Write-Host "  ver ideas          Mostrar tus ideas"
    Write-Host "  ver tareas         Mostrar tareas pendientes"
    Write-Host "  ver recuerdos      Mostrar lo que Jarvis recuerda"
    Write-Host "  completar <codigo> Marcar una tarea como completada"
    Write-Host "  borrar <codigo>    Eliminar cualquier registro"
    Write-Host "  ayuda              Mostrar esta guia"
    Write-Host "  salir              Cerrar Jarvis"
    Write-Host ""
}

function Invoke-JarvisCommand {
    param([string]$InputText)

    $cleanInput = $InputText.Trim()
    switch -Regex ($cleanInput) {
        "^idea\s+(.+)$"       { Add-Record -Type "idea" -Text $Matches[1]; return $true }
        "^tarea\s+(.+)$"      { Add-Record -Type "tarea" -Text $Matches[1]; return $true }
        "^record[aá]\s+(.+)$" { Add-Record -Type "recuerdo" -Text $Matches[1]; return $true }
        "^ver\s+ideas$"       { Show-Records -Type "idea"; return $true }
        "^ver\s+tareas$"      { Show-Records -Type "tarea"; return $true }
        "^ver\s+recuerdos$"   { Show-Records -Type "recuerdo"; return $true }
        "^completar\s+(\S+)$" { Complete-Task -Id $Matches[1]; return $true }
        "^borrar\s+(\S+)$"    { Remove-Record -Id $Matches[1]; return $true }
        "^ayuda$"             { Show-Help; return $true }
        "^salir$"             { return $false }
        "^$"                  { return $true }
        default {
            Write-Host "No entendi ese comando. Escribi 'ayuda' para ver ejemplos." -ForegroundColor Yellow
            return $true
        }
    }
}

Initialize-Storage

if ($Command.Count -gt 0) {
    foreach ($item in $Command) {
        if (-not (Invoke-JarvisCommand -InputText $item)) {
            break
        }
    }
    exit
}

Write-Host ""
Write-Host "Jarvis 0.1" -ForegroundColor Cyan
Write-Host "Tu asistente local esta listo. Escribi 'ayuda' para ver los comandos."
Write-Host ""

$keepRunning = $true
while ($keepRunning) {
    $userInput = Read-Host "Vos"
    $keepRunning = Invoke-JarvisCommand -InputText $userInput
}

Write-Host "Hasta luego."
