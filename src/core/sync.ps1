# Infraestructura de sincronizacion local-first.
# Registra cambios por entidad para que cada modulo pueda sincronizarse de forma incremental.

function Initialize-JarvisSyncStorage {
    $script:JarvisSyncDirectory = Join-Path $script:JarvisDataDirectory "sync"
    $script:JarvisSyncChangesFile = Join-Path $script:JarvisSyncDirectory "changes.json"
    $script:JarvisSyncConflictsFile = Join-Path $script:JarvisSyncDirectory "conflicts.json"

    if (-not (Test-Path -LiteralPath $script:JarvisSyncDirectory)) {
        New-Item -ItemType Directory -Path $script:JarvisSyncDirectory | Out-Null
    }
    if (-not (Test-Path -LiteralPath $script:JarvisSyncChangesFile)) {
        "[]" | Set-Content -LiteralPath $script:JarvisSyncChangesFile -Encoding UTF8
    }
    if (-not (Test-Path -LiteralPath $script:JarvisSyncConflictsFile)) {
        "[]" | Set-Content -LiteralPath $script:JarvisSyncConflictsFile -Encoding UTF8
    }
    if (-not (Test-Path -LiteralPath $script:JarvisIdentityFile)) {
        Initialize-JarvisStorage -ProjectRoot $script:JarvisProjectRoot
    }
}

function Read-JarvisIdentity {
    Initialize-JarvisSyncStorage
    return ConvertFrom-Json -InputObject (Get-Content -LiteralPath $script:JarvisIdentityFile -Raw)
}

function Write-JarvisIdentity {
    param($Identity)

    $Identity | Add-Member -NotePropertyName "updated_at" -NotePropertyValue (Get-JarvisIsoNow) -Force
    ConvertTo-Json -InputObject $Identity -Depth 12 |
        Set-Content -LiteralPath $script:JarvisIdentityFile -Encoding UTF8
}

function Get-JarvisWorkspaceId {
    return [string](Read-JarvisIdentity).workspace_id
}

function Get-JarvisSyncSecret {
    return [string](Read-JarvisIdentity).sync_secret
}

function Get-JarvisDeviceName {
    return [string](Read-JarvisIdentity).device_name
}

function Set-JarvisDeviceName {
    param([string]$DeviceName)

    $identity = Read-JarvisIdentity
    $safeName = Get-JarvisSafeText -Value $DeviceName -Fallback "Dispositivo Jarvis"
    $identity.device_name = $safeName
    foreach ($device in @($identity.linked_devices)) {
        if ($device.device_id -eq $identity.device_id) {
            $device.device_name = $safeName
        }
    }
    Write-JarvisIdentity -Identity $identity
    return $identity
}

function Set-JarvisWorkspaceName {
    param([string]$WorkspaceName)

    $identity = Read-JarvisIdentity
    $identity.workspace_name = Get-JarvisSafeText -Value $WorkspaceName -Fallback "Mi Jarvis"
    Write-JarvisIdentity -Identity $identity
    return $identity
}

function Test-JarvisDeviceAuthorized {
    param(
        $Identity,
        [string]$DeviceId
    )

    if ([string]::IsNullOrWhiteSpace($DeviceId)) {
        return $false
    }

    return @($Identity.linked_devices | Where-Object { $_.device_id -eq $DeviceId }).Count -gt 0
}

function Add-JarvisLinkedDevice {
    param(
        [string]$DeviceId,
        [string]$DeviceName
    )

    $identity = Read-JarvisIdentity
    if (-not (Test-JarvisDeviceAuthorized -Identity $identity -DeviceId $DeviceId)) {
        $devices = @($identity.linked_devices)
        $devices += [pscustomobject]@{
            device_id = $DeviceId
            device_name = (Get-JarvisSafeText -Value $DeviceName -Fallback "Dispositivo vinculado")
            linked_at = Get-JarvisIsoNow
            last_seen_at = $null
        }
        $identity.linked_devices = @($devices)
    }
    else {
        foreach ($device in @($identity.linked_devices)) {
            if ($device.device_id -eq $DeviceId -and -not [string]::IsNullOrWhiteSpace($DeviceName)) {
                $device.device_name = $DeviceName
            }
        }
    }
    Write-JarvisIdentity -Identity $identity
    return $identity
}

function Update-JarvisLinkedDeviceSeen {
    param(
        [string]$DeviceId,
        [string]$DeviceName = ""
    )

    $identity = Read-JarvisIdentity
    foreach ($device in @($identity.linked_devices)) {
        if ($device.device_id -eq $DeviceId) {
            if (-not [string]::IsNullOrWhiteSpace($DeviceName)) {
                $device.device_name = $DeviceName
            }
            $device.last_seen_at = Get-JarvisIsoNow
        }
    }
    Write-JarvisIdentity -Identity $identity
    return $identity
}

function New-JarvisPairingCode {
    param([int]$Minutes = 10)

    $identity = Read-JarvisIdentity
    $code = (Get-Random -Minimum 100000 -Maximum 999999).ToString()
    $expiresAt = (Get-Date).AddMinutes($Minutes).ToString("yyyy-MM-ddTHH:mm:ss")
    $identity | Add-Member -NotePropertyName "pairing_code" -NotePropertyValue $code -Force
    $identity | Add-Member -NotePropertyName "pairing_expires_at" -NotePropertyValue $expiresAt -Force
    Write-JarvisIdentity -Identity $identity

    return [pscustomobject]@{
        pairing_code = $code
        workspace_id = $identity.workspace_id
        workspace_name = $identity.workspace_name
        expires_at = $expiresAt
    }
}

function ConvertFrom-JarvisPairingCode {
    param([string]$Code)

    $base64 = $Code.Trim() -replace "-", "+" -replace "_", "/"
    while ($base64.Length % 4 -ne 0) {
        $base64 += "="
    }
    $json = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($base64))
    return ConvertFrom-Json -InputObject $json
}

function Complete-JarvisPairing {
    param(
        [string]$PairingCode,
        [string]$DeviceId,
        [string]$DeviceName
    )

    $identity = Read-JarvisIdentity
    $safeCode = (Get-JarvisSafeText -Value $PairingCode) -replace "\s", ""
    $storedCode = Get-JarvisSafeText -Value $identity.pairing_code
    if ([string]::IsNullOrWhiteSpace($storedCode)) {
        throw "No hay un codigo de vinculacion activo. Genera uno nuevo desde la notebook."
    }
    if ($safeCode -ne $storedCode) {
        throw "Codigo de vinculacion invalido."
    }
    if (([datetime]::Parse($identity.pairing_expires_at)) -lt (Get-Date)) {
        throw "El codigo de vinculacion expiro."
    }

    Add-JarvisLinkedDevice -DeviceId $DeviceId -DeviceName $DeviceName | Out-Null
    $identity = Read-JarvisIdentity
    $identity | Add-Member -NotePropertyName "pairing_code" -NotePropertyValue $null -Force
    $identity | Add-Member -NotePropertyName "pairing_token" -NotePropertyValue $null -Force
    $identity | Add-Member -NotePropertyName "pairing_expires_at" -NotePropertyValue $null -Force
    Write-JarvisIdentity -Identity $identity

    return [pscustomobject]@{
        workspace_id = $identity.workspace_id
        workspace_name = $identity.workspace_name
        sync_secret = $identity.sync_secret
        device_id = $DeviceId
        linked_devices = @($identity.linked_devices)
    }
}

function Test-JarvisSyncAuth {
    param(
        [string]$WorkspaceId,
        [string]$DeviceId,
        [string]$SyncSecret
    )

    $identity = Read-JarvisIdentity
    if ($WorkspaceId -ne $identity.workspace_id) {
        return [pscustomobject]@{ ok = $false; status = 403; error = "Workspace incorrecto." }
    }
    if ($SyncSecret -ne $identity.sync_secret) {
        return [pscustomobject]@{ ok = $false; status = 401; error = "Token de sincronizacion invalido." }
    }
    if (-not (Test-JarvisDeviceAuthorized -Identity $identity -DeviceId $DeviceId)) {
        return [pscustomobject]@{ ok = $false; status = 403; error = "Dispositivo no autorizado para este Jarvis." }
    }

    return [pscustomobject]@{ ok = $true; status = 200; error = "" }
}

function Get-JarvisIdentityPublic {
    $identity = Read-JarvisIdentity
    return [pscustomobject]@{
        workspace_id = $identity.workspace_id
        workspace_name = $identity.workspace_name
        device_id = $identity.device_id
        device_name = $identity.device_name
        linked_devices = @($identity.linked_devices)
    }
}

function Read-JarvisSyncJsonArray {
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

function Write-JarvisSyncJsonArray {
    param(
        [string]$Path,
        [array]$Items
    )

    ConvertTo-Json -InputObject $Items -Depth 12 |
        Set-Content -LiteralPath $Path -Encoding UTF8
}

function Read-JarvisSyncChanges {
    Initialize-JarvisSyncStorage
    return Read-JarvisSyncJsonArray -Path $script:JarvisSyncChangesFile
}

function Write-JarvisSyncChanges {
    param([array]$Changes)

    Initialize-JarvisSyncStorage
    Write-JarvisSyncJsonArray -Path $script:JarvisSyncChangesFile -Items $Changes
}

function Read-JarvisSyncConflicts {
    Initialize-JarvisSyncStorage
    return Read-JarvisSyncJsonArray -Path $script:JarvisSyncConflictsFile
}

function Write-JarvisSyncConflicts {
    param([array]$Conflicts)

    Initialize-JarvisSyncStorage
    Write-JarvisSyncJsonArray -Path $script:JarvisSyncConflictsFile -Items $Conflicts
}

function Get-JarvisIsoNow {
    return (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
}

function Get-JarvisChangeValue {
    param($Value)

    if ($null -eq $Value) {
        return [pscustomobject]@{}
    }

    return $Value | ConvertTo-Json -Depth 12 | ConvertFrom-Json
}

function Add-JarvisSyncChange {
    param(
        [string]$Entity,
        [string]$EntityId,
        [string]$Operation,
        $Value,
        [string]$DeviceId = (Get-JarvisDeviceId),
        [string]$CreatedAt = (Get-JarvisIsoNow)
    )

    if ([string]::IsNullOrWhiteSpace($Entity) -or [string]::IsNullOrWhiteSpace($EntityId)) {
        return $null
    }

    $changes = @(Read-JarvisSyncChanges)
    $change = [pscustomobject]@{
        change_id = "change-$([guid]::NewGuid().ToString("N"))"
        entity = $Entity
        entity_id = $EntityId
        operation = $Operation
        value = Get-JarvisChangeValue -Value $Value
        workspace_id = Get-JarvisWorkspaceId
        device_id = $DeviceId
        created_at = $CreatedAt
        applied_at = $CreatedAt
    }

    $changes += $change
    Write-JarvisSyncChanges -Changes $changes
    return $change
}

function Add-JarvisSyncConflict {
    param(
        [string]$Entity,
        [string]$EntityId,
        $LocalValue,
        $RemoteValue,
        [string]$Reason,
        [string]$RemoteChangeId = ""
    )

    $conflicts = @(Read-JarvisSyncConflicts)
    $conflict = [pscustomobject]@{
        conflict_id = "conflict-$([guid]::NewGuid().ToString("N"))"
        entity = $Entity
        entity_id = $EntityId
        reason = $Reason
        remote_change_id = $RemoteChangeId
        local_value = Get-JarvisChangeValue -Value $LocalValue
        remote_value = Get-JarvisChangeValue -Value $RemoteValue
        created_at = Get-JarvisIsoNow
    }

    $conflicts += $conflict
    Write-JarvisSyncConflicts -Conflicts $conflicts
    return $conflict
}

function Get-JarvisSyncEntityStore {
    param([string]$Entity)

    switch ($Entity) {
        "records" {
            return [pscustomobject]@{
                entity = "records"
                read = { Read-JarvisRecords }
                write = { param($Items) Write-JarvisRecords -Records $Items -BackupReason "sync-apply" }
            }
        }
        "finance_movements" {
            if (Get-Command Read-FinanceMovements -ErrorAction SilentlyContinue) {
                return [pscustomobject]@{
                    entity = "finance_movements"
                    read = { Read-FinanceMovements }
                    write = { param($Items) Write-FinanceMovements -Movements $Items -BackupReason "sync-apply" }
                }
            }
        }
        "finance_settings" {
            if (Get-Command Read-FinanceSettings -ErrorAction SilentlyContinue) {
                return [pscustomobject]@{
                    entity = "finance_settings"
                    read = { @(Read-FinanceSettings | Add-Member -NotePropertyName "id" -NotePropertyValue "main" -Force -PassThru) }
                    write = { param($Items) if (@($Items).Count -gt 0) { Write-FinanceSettings -Settings @($Items)[0] -BackupReason "sync-apply" } }
                }
            }
        }
        "finance_payment_methods" {
            if (Get-Command Read-FinancePaymentMethods -ErrorAction SilentlyContinue) {
                return [pscustomobject]@{
                    entity = "finance_payment_methods"
                    read = { Read-FinancePaymentMethods }
                    write = { param($Items) Write-FinancePaymentMethods -PaymentMethods $Items -BackupReason "sync-apply" }
                }
            }
        }
    }

    return $null
}

function Get-JarvisValueDate {
    param(
        $Value,
        [string]$Name,
        [datetime]$Fallback = ([datetime]"1970-01-01")
    )

    try {
        $text = Get-JarvisSafeText -Value $Value.$Name
        if ([string]::IsNullOrWhiteSpace($text)) {
            return $Fallback
        }
        return [datetime]::Parse($text)
    }
    catch {
        return $Fallback
    }
}

function Test-JarvisRemoteWins {
    param(
        $LocalValue,
        $RemoteValue
    )

    $localDeleted = Get-JarvisValueDate -Value $LocalValue -Name "deleted_at"
    $remoteDeleted = Get-JarvisValueDate -Value $RemoteValue -Name "deleted_at"
    if ($remoteDeleted -gt $localDeleted -and $remoteDeleted -gt (Get-JarvisValueDate -Value $LocalValue -Name "updated_at")) {
        return $true
    }

    $localUpdated = Get-JarvisValueDate -Value $LocalValue -Name "updated_at"
    $remoteUpdated = Get-JarvisValueDate -Value $RemoteValue -Name "updated_at"
    return $remoteUpdated -gt $localUpdated
}

function Ensure-JarvisBaselineSyncChanges {
    $changes = @(Read-JarvisSyncChanges)
    $known = @{}
    foreach ($change in $changes) {
        $known["$($change.entity)|$($change.entity_id)"] = $true
    }

    $added = 0
    $entities = @("records", "finance_movements", "finance_settings", "finance_payment_methods")
    foreach ($entity in $entities) {
        $store = Get-JarvisSyncEntityStore -Entity $entity
        if (-not $store) { continue }

        foreach ($item in @(& $store.read)) {
            if (-not $item.id) { continue }
            $key = "$entity|$($item.id)"
            if ($known.ContainsKey($key)) { continue }

            $changes += [pscustomobject]@{
                change_id = "change-$([guid]::NewGuid().ToString("N"))"
                entity = $entity
                entity_id = [string]$item.id
                operation = "baseline"
                value = Get-JarvisChangeValue -Value $item
                workspace_id = Get-JarvisWorkspaceId
                device_id = Get-JarvisDeviceId
                created_at = (Get-JarvisSafeText -Value $item.updated_at -Fallback (Get-JarvisIsoNow))
                applied_at = Get-JarvisIsoNow
            }
            $known[$key] = $true
            $added += 1
        }
    }

    if ($added -gt 0) {
        Write-JarvisSyncChanges -Changes $changes
    }
}

function Apply-JarvisIncomingChange {
    param($Change)

    $store = Get-JarvisSyncEntityStore -Entity $Change.entity
    if (-not $store) {
        return [pscustomobject]@{ status = "rejected"; reason = "Entidad no soportada"; change_id = $Change.change_id }
    }

    $items = @(& $store.read)
    $remote = Get-JarvisChangeValue -Value $Change.value
    if (-not $remote.id) {
        $remote | Add-Member -NotePropertyName "id" -NotePropertyValue $Change.entity_id -Force
    }

    $local = $items | Where-Object { $_.id -eq $Change.entity_id } | Select-Object -First 1
    if (-not $local) {
        $items += $remote
        & $store.write $items
        return [pscustomobject]@{ status = "accepted"; reason = "created"; change_id = $Change.change_id }
    }

    if (Test-JarvisRemoteWins -LocalValue $local -RemoteValue $remote) {
        $merged = @()
        foreach ($item in $items) {
            if ($item.id -eq $Change.entity_id) {
                $merged += $remote
            }
            else {
                $merged += $item
            }
        }
        & $store.write $merged
        return [pscustomobject]@{ status = "accepted"; reason = "updated"; change_id = $Change.change_id }
    }

    $localUpdated = Get-JarvisValueDate -Value $local -Name "updated_at"
    $remoteUpdated = Get-JarvisValueDate -Value $remote -Name "updated_at"
    if ($remoteUpdated -lt $localUpdated) {
        $conflict = Add-JarvisSyncConflict -Entity $Change.entity -EntityId $Change.entity_id -LocalValue $local -RemoteValue $remote -Reason "local-newer-than-remote" -RemoteChangeId $Change.change_id
        return [pscustomobject]@{ status = "conflict"; reason = $conflict.reason; change_id = $Change.change_id; conflict_id = $conflict.conflict_id }
    }

    return [pscustomobject]@{ status = "skipped"; reason = "duplicate-or-same-version"; change_id = $Change.change_id }
}

function Resolve-JarvisSyncConflict {
    param(
        [string]$ConflictId,
        [string]$Resolution
    )

    $conflicts = @(Read-JarvisSyncConflicts)
    $conflict = $conflicts | Where-Object { $_.conflict_id -eq $ConflictId } | Select-Object -First 1
    if (-not $conflict) {
        throw "No encontre ese conflicto."
    }

    if ($Resolution -eq "remote") {
        $store = Get-JarvisSyncEntityStore -Entity $conflict.entity
        if (-not $store) {
            throw "Entidad no soportada."
        }

        $items = @(& $store.read)
        $remote = Get-JarvisChangeValue -Value $conflict.remote_value
        $merged = @()
        $found = $false
        foreach ($item in $items) {
            if ($item.id -eq $conflict.entity_id) {
                $merged += $remote
                $found = $true
            }
            else {
                $merged += $item
            }
        }
        if (-not $found) {
            $merged += $remote
        }
        & $store.write $merged
        Add-JarvisSyncChange -Entity $conflict.entity -EntityId $conflict.entity_id -Operation "resolve-remote" -Value $remote | Out-Null
    }

    $remaining = @($conflicts | Where-Object { $_.conflict_id -ne $ConflictId })
    Write-JarvisSyncConflicts -Conflicts $remaining
    return @($remaining)
}

function Apply-JarvisSyncChanges {
    param(
        [array]$Changes,
        [string]$RemoteDeviceId = ""
    )

    Ensure-JarvisBaselineSyncChanges
    $localDeviceId = Get-JarvisDeviceId
    $existingChanges = @(Read-JarvisSyncChanges)
    $existingIds = @{}
    foreach ($change in $existingChanges) {
        $existingIds[$change.change_id] = $true
    }

    $results = @()
    foreach ($change in @($Changes)) {
        if (-not $change -or [string]::IsNullOrWhiteSpace((Get-JarvisSafeText -Value $change.change_id))) {
            continue
        }
        if ((Get-JarvisSafeText -Value $change.workspace_id) -ne (Get-JarvisWorkspaceId)) {
            $results += [pscustomobject]@{ status = "rejected"; reason = "workspace-mismatch"; change_id = $change.change_id }
            continue
        }
        if ($change.device_id -eq $localDeviceId) {
            $results += [pscustomobject]@{ status = "skipped"; reason = "own-change"; change_id = $change.change_id }
            continue
        }
        if ($existingIds.ContainsKey($change.change_id)) {
            $results += [pscustomobject]@{ status = "skipped"; reason = "already-seen"; change_id = $change.change_id }
            continue
        }

        $result = Apply-JarvisIncomingChange -Change $change
        $results += $result
        if (@("accepted", "skipped", "conflict") -contains $result.status) {
            $existingChanges += [pscustomobject]@{
                change_id = $change.change_id
                entity = $change.entity
                entity_id = $change.entity_id
                operation = $change.operation
                value = Get-JarvisChangeValue -Value $change.value
                workspace_id = Get-JarvisWorkspaceId
                device_id = (Get-JarvisSafeText -Value $change.device_id -Fallback $RemoteDeviceId)
                created_at = (Get-JarvisSafeText -Value $change.created_at -Fallback (Get-JarvisIsoNow))
                applied_at = Get-JarvisIsoNow
            }
            $existingIds[$change.change_id] = $true
        }
    }

    Write-JarvisSyncChanges -Changes $existingChanges
    return @($results)
}

function Get-JarvisSyncChangesSince {
    param(
        [string]$Since = "",
        [string]$ExcludeDeviceId = ""
    )

    Ensure-JarvisBaselineSyncChanges
    $sinceDate = Get-JarvisValueDate -Value ([pscustomobject]@{ since = $Since }) -Name "since"
    return @(Read-JarvisSyncChanges | Where-Object {
        $createdAt = Get-JarvisValueDate -Value $_ -Name "created_at"
        $createdAt -gt $sinceDate -and
            ([string]::IsNullOrWhiteSpace($ExcludeDeviceId) -or $_.device_id -ne $ExcludeDeviceId)
    } | Sort-Object created_at)
}

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
    Ensure-JarvisBaselineSyncChanges
    $pendingRecords = @(Get-JarvisPendingSyncRecords)
    $pendingMovements = @(Get-JarvisPendingSyncFinanceMovements)
    $changes = @(Read-JarvisSyncChanges)
    $conflicts = @(Read-JarvisSyncConflicts)

    return [pscustomobject]@{
        device_id = Get-JarvisDeviceId
        device_name = Get-JarvisDeviceName
        workspace_id = Get-JarvisWorkspaceId
        workspace_name = (Read-JarvisIdentity).workspace_name
        linked_devices = @((Read-JarvisIdentity).linked_devices)
        legacy_pending_records = $pendingRecords.Count
        legacy_pending_finance_movements = $pendingMovements.Count
        legacy_pending_total = $pendingRecords.Count + $pendingMovements.Count
        change_count = $changes.Count
        conflict_count = $conflicts.Count
        transport = "local-lan-http"
        ready_for_exchange = $true
    }
}

function Get-JarvisSyncChanges {
    Ensure-JarvisBaselineSyncChanges
    return [pscustomobject]@{
        device_id = Get-JarvisDeviceId
        generated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
        changes = @(Read-JarvisSyncChanges)
    }
}
