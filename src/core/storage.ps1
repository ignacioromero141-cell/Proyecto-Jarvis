# Capa de almacenamiento: sabe donde viven los datos y como leer/escribir JSON.
# La idea es que las pantallas no tengan que conocer estos detalles.

function Initialize-JarvisStorage {
    param([string]$ProjectRoot)

    $script:JarvisProjectRoot = $ProjectRoot
    $script:JarvisDataDirectory = Join-Path $ProjectRoot "data"
    $script:JarvisDataFile = Join-Path $script:JarvisDataDirectory "records.json"
    $script:JarvisDeviceFile = Join-Path $script:JarvisDataDirectory "device-id.txt"
    $script:JarvisBackupDirectory = Join-Path $script:JarvisDataDirectory "backups"

    if (-not (Test-Path -LiteralPath $script:JarvisDataDirectory)) {
        New-Item -ItemType Directory -Path $script:JarvisDataDirectory | Out-Null
    }
    if (-not (Test-Path -LiteralPath $script:JarvisBackupDirectory)) {
        New-Item -ItemType Directory -Path $script:JarvisBackupDirectory | Out-Null
    }
    if (-not (Test-Path -LiteralPath $script:JarvisDataFile)) {
        "[]" | Set-Content -LiteralPath $script:JarvisDataFile -Encoding UTF8
    }
    if (-not (Test-Path -LiteralPath $script:JarvisDeviceFile)) {
        "notebook-$([guid]::NewGuid().ToString("N"))" | Set-Content -LiteralPath $script:JarvisDeviceFile -Encoding UTF8
    }
}

function Get-JarvisDeviceId {
    if (-not (Test-Path -LiteralPath $script:JarvisDeviceFile)) {
        "notebook-$([guid]::NewGuid().ToString("N"))" | Set-Content -LiteralPath $script:JarvisDeviceFile -Encoding UTF8
    }

    return (Get-Content -LiteralPath $script:JarvisDeviceFile -Raw).Trim()
}

function Read-JarvisRecords {
    $content = Get-Content -LiteralPath $script:JarvisDataFile -Raw
    if ([string]::IsNullOrWhiteSpace($content)) {
        return @()
    }

    $records = ConvertFrom-Json -InputObject $content
    return @($records | ForEach-Object { $_ })
}

function New-JarvisDataBackup {
    param([string]$Reason = "auto")

    if (-not (Test-Path -LiteralPath $script:JarvisDataFile)) {
        return $null
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $safeReason = $Reason -replace "[^a-zA-Z0-9_-]", "-"
    $backupFile = Join-Path $script:JarvisBackupDirectory "records-$safeReason-$timestamp.json"
    Copy-Item -LiteralPath $script:JarvisDataFile -Destination $backupFile
    return $backupFile
}

function Write-JarvisRecords {
    param(
        [array]$Records,
        [string]$BackupReason = "auto"
    )

    New-JarvisDataBackup -Reason $BackupReason | Out-Null
    ConvertTo-Json -InputObject $Records -Depth 6 |
        Set-Content -LiteralPath $script:JarvisDataFile -Encoding UTF8
}

function Get-JarvisSafeText {
    param(
        $Value,
        [string]$Fallback = ""
    )

    if ($null -eq $Value) {
        return $Fallback
    }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $Fallback
    }

    return $text
}

function Get-JarvisSafeDateText {
    param(
        $Value,
        [string]$Format
    )

    try {
        $fallbackDate = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
        $dateText = Get-JarvisSafeText -Value $Value -Fallback $fallbackDate
        return ([datetime]::Parse($dateText)).ToString($Format)
    }
    catch {
        return "sin fecha"
    }
}

function Test-JarvisDateIsToday {
    param($Value)

    try {
        $dateText = Get-JarvisSafeText -Value $Value
        return ([datetime]::Parse($dateText)).Date -eq (Get-Date).Date
    }
    catch {
        return $false
    }
}
