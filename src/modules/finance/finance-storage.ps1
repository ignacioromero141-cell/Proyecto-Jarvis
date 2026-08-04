# Almacenamiento del modulo Finanzas.
# Mantiene los archivos financieros separados de records.json.

function Initialize-FinanceStorage {
    param([string]$ProjectRoot)

    $script:FinanceProjectRoot = $ProjectRoot
    $script:FinanceDataDirectory = Join-Path $ProjectRoot "data\finance"
    $script:FinanceBackupDirectory = Join-Path $script:FinanceDataDirectory "backups"
    $script:FinanceMovementsFile = Join-Path $script:FinanceDataDirectory "movements.json"
    $script:FinanceCategoriesFile = Join-Path $script:FinanceDataDirectory "categories.json"
    $script:FinancePrioritiesFile = Join-Path $script:FinanceDataDirectory "priorities.json"
    $script:FinanceSettingsFile = Join-Path $script:FinanceDataDirectory "settings.json"

    if (-not (Test-Path -LiteralPath $script:FinanceDataDirectory)) {
        New-Item -ItemType Directory -Path $script:FinanceDataDirectory | Out-Null
    }
    if (-not (Test-Path -LiteralPath $script:FinanceBackupDirectory)) {
        New-Item -ItemType Directory -Path $script:FinanceBackupDirectory | Out-Null
    }
    if (-not (Test-Path -LiteralPath $script:FinanceMovementsFile)) {
        "[]" | Set-Content -LiteralPath $script:FinanceMovementsFile -Encoding UTF8
    }
}

function Read-FinanceJsonArray {
    param([string]$Path)

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

function Read-FinanceJsonObject {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{}
    }

    $content = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($content)) {
        return [pscustomobject]@{}
    }

    return ConvertFrom-Json -InputObject $content
}

function New-FinanceBackup {
    param([string]$Reason = "auto")

    if (-not (Test-Path -LiteralPath $script:FinanceMovementsFile)) {
        return $null
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $safeReason = $Reason -replace "[^a-zA-Z0-9_-]", "-"
    $backupFile = Join-Path $script:FinanceBackupDirectory "movements-$safeReason-$timestamp.json"
    Copy-Item -LiteralPath $script:FinanceMovementsFile -Destination $backupFile
    return $backupFile
}

function Read-FinanceMovements {
    return Read-FinanceJsonArray -Path $script:FinanceMovementsFile
}

function Write-FinanceMovements {
    param(
        [array]$Movements,
        [string]$BackupReason = "finance-auto"
    )

    New-FinanceBackup -Reason $BackupReason | Out-Null
    ConvertTo-Json -InputObject $Movements -Depth 8 |
        Set-Content -LiteralPath $script:FinanceMovementsFile -Encoding UTF8
}

function Read-FinanceCategories {
    return Read-FinanceJsonArray -Path $script:FinanceCategoriesFile
}

function Read-FinancePriorities {
    return Read-FinanceJsonArray -Path $script:FinancePrioritiesFile
}

function Read-FinanceSettings {
    return Read-FinanceJsonObject -Path $script:FinanceSettingsFile
}

function Write-FinanceSettings {
    param(
        $Settings,
        [string]$BackupReason = "settings-update"
    )

    if (Test-Path -LiteralPath $script:FinanceSettingsFile) {
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $backupFile = Join-Path $script:FinanceBackupDirectory "settings-$BackupReason-$timestamp.json"
        Copy-Item -LiteralPath $script:FinanceSettingsFile -Destination $backupFile
    }

    ConvertTo-Json -InputObject $Settings -Depth 8 |
        Set-Content -LiteralPath $script:FinanceSettingsFile -Encoding UTF8
}
