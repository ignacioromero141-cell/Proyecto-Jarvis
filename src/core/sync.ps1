# Base de sincronizacion local-first.
# Todavia no aplica cambios remotos: solo expone estado y cambios pendientes.

function Test-JarvisNeedsSync {
    param($Value)

    return [string]::IsNullOrWhiteSpace((Get-JarvisSafeText -Value $Value.synced_at))
}

function Get-JarvisPendingSyncRecords {
    return @(Read-JarvisRecords | Where-Object { Test-JarvisNeedsSync -Value $_ })
}

function Get-JarvisPendingSyncFinanceMovements {
    if (-not (Get-Command Read-FinanceMovements -ErrorAction SilentlyContinue)) {
        return @()
    }

    return @(Read-FinanceMovements | Where-Object { Test-JarvisNeedsSync -Value $_ })
}

function Get-JarvisSyncStatus {
    $pendingRecords = @(Get-JarvisPendingSyncRecords)
    $pendingMovements = @(Get-JarvisPendingSyncFinanceMovements)

    return [pscustomobject]@{
        device_id = Get-JarvisDeviceId
        pending_records = $pendingRecords.Count
        pending_finance_movements = $pendingMovements.Count
        pending_total = $pendingRecords.Count + $pendingMovements.Count
        transport = "local-manual-future"
        ready_for_exchange = $true
    }
}

function Get-JarvisSyncChanges {
    return [pscustomobject]@{
        device_id = Get-JarvisDeviceId
        generated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
        records = @(Get-JarvisPendingSyncRecords)
        finance_movements = @(Get-JarvisPendingSyncFinanceMovements)
    }
}
