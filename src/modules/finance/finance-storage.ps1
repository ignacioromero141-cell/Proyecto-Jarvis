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
    $script:FinancePaymentMethodsFile = Join-Path $script:FinanceDataDirectory "payment-methods.json"
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
    if (-not (Test-Path -LiteralPath $script:FinancePaymentMethodsFile)) {
        ConvertTo-Json -InputObject (Get-FinanceDefaultPaymentMethods) -Depth 8 |
            Set-Content -LiteralPath $script:FinancePaymentMethodsFile -Encoding UTF8
    }
}

function Get-FinanceDefaultPaymentMethods {
    $now = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    return @(
        [pscustomobject]@{ id = "cash"; label = "Efectivo"; enabled = $true; built_in = $true; sort_order = 10; deleted_at = $null; created_at = $now; updated_at = $now },
        [pscustomobject]@{ id = "debit"; label = "Debito"; enabled = $true; built_in = $true; sort_order = 20; deleted_at = $null; created_at = $now; updated_at = $now },
        [pscustomobject]@{ id = "credit"; label = "Credito"; enabled = $true; built_in = $true; sort_order = 30; deleted_at = $null; created_at = $now; updated_at = $now },
        [pscustomobject]@{ id = "transfer"; label = "Transferencia"; enabled = $true; built_in = $true; sort_order = 40; deleted_at = $null; created_at = $now; updated_at = $now },
        [pscustomobject]@{ id = "wallet"; label = "Billetera virtual"; enabled = $true; built_in = $true; sort_order = 50; deleted_at = $null; created_at = $now; updated_at = $now }
    )
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

function Read-FinancePaymentMethods {
    return Read-FinanceJsonArray -Path $script:FinancePaymentMethodsFile
}

function Write-FinancePaymentMethods {
    param(
        [array]$PaymentMethods,
        [string]$BackupReason = "payment-methods-update"
    )

    if (Test-Path -LiteralPath $script:FinancePaymentMethodsFile) {
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $safeReason = $BackupReason -replace "[^a-zA-Z0-9_-]", "-"
        $backupFile = Join-Path $script:FinanceBackupDirectory "payment-methods-$safeReason-$timestamp.json"
        Copy-Item -LiteralPath $script:FinancePaymentMethodsFile -Destination $backupFile
    }

    ConvertTo-Json -InputObject $PaymentMethods -Depth 8 |
        Set-Content -LiteralPath $script:FinancePaymentMethodsFile -Encoding UTF8
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
