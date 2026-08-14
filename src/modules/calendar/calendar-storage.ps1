# Almacenamiento del modulo Calendario.

function Initialize-CalendarStorage {
    param([string]$ProjectRoot)

    $script:CalendarProjectRoot = $ProjectRoot
    $script:CalendarDataDirectory = Join-Path $ProjectRoot "data\calendar"
    $script:CalendarBackupDirectory = Join-Path $script:CalendarDataDirectory "backups"
    $script:CalendarEventsFile = Join-Path $script:CalendarDataDirectory "events.json"

    if (-not (Test-Path -LiteralPath $script:CalendarDataDirectory)) {
        New-Item -ItemType Directory -Path $script:CalendarDataDirectory | Out-Null
    }
    if (-not (Test-Path -LiteralPath $script:CalendarBackupDirectory)) {
        New-Item -ItemType Directory -Path $script:CalendarBackupDirectory | Out-Null
    }
    if (-not (Test-Path -LiteralPath $script:CalendarEventsFile)) {
        "[]" | Set-Content -LiteralPath $script:CalendarEventsFile -Encoding UTF8
    }
}

function Read-CalendarJsonArray {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return @()
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        return @()
    }

    $content = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($content)) {
        return @()
    }

    $items = ConvertFrom-Json -InputObject $content
    return @($items | ForEach-Object { $_ })
}

function Read-CalendarEvents {
    return Read-CalendarJsonArray -Path $script:CalendarEventsFile
}

function Write-CalendarEvents {
    param(
        [array]$Events,
        [string]$BackupReason = "events-update"
    )

    if (Test-Path -LiteralPath $script:CalendarEventsFile) {
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $safeReason = $BackupReason -replace "[^a-zA-Z0-9_-]", "-"
        $backupFile = Join-Path $script:CalendarBackupDirectory "events-$safeReason-$timestamp.json"
        Copy-Item -LiteralPath $script:CalendarEventsFile -Destination $backupFile
    }

    ConvertTo-Json -InputObject $Events -Depth 12 |
        Set-Content -LiteralPath $script:CalendarEventsFile -Encoding UTF8
}
