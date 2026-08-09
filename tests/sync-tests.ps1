param()

$ErrorActionPreference = "Stop"
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. (Join-Path $ProjectRoot "src\web\server.ps1")

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function New-TestRoot {
    $root = Join-Path $env:TEMP "jarvis-sync-test-$([guid]::NewGuid().ToString("N"))"
    New-Item -ItemType Directory -Path $root | Out-Null
    return $root
}

function Initialize-TestJarvis {
    param([string]$Root)

    Initialize-JarvisStorage -ProjectRoot $Root
    Initialize-FinanceStorage -ProjectRoot $Root
    Initialize-JarvisSyncStorage
}

$root = New-TestRoot
Initialize-TestJarvis -Root $root

$identity = Read-JarvisIdentity
Assert-True ($identity.workspace_id -like "workspace-*") "workspace_id no fue generado."
Assert-True ($identity.device_id -like "notebook-*") "device_id no fue generado."
Assert-True (-not [string]::IsNullOrWhiteSpace($identity.sync_secret)) "sync_secret no fue generado."

$authOk = Test-JarvisSyncAuth -WorkspaceId $identity.workspace_id -DeviceId $identity.device_id -SyncSecret $identity.sync_secret
Assert-True $authOk.ok "La autenticacion valida fue rechazada."

$authBadWorkspace = Test-JarvisSyncAuth -WorkspaceId "workspace-otro" -DeviceId $identity.device_id -SyncSecret $identity.sync_secret
Assert-True (-not $authBadWorkspace.ok -and $authBadWorkspace.status -eq 403) "Workspace incorrecto no fue rechazado."

$authBadToken = Test-JarvisSyncAuth -WorkspaceId $identity.workspace_id -DeviceId $identity.device_id -SyncSecret "token-malo"
Assert-True (-not $authBadToken.ok -and $authBadToken.status -eq 401) "Token incorrecto no fue rechazado."

$authBadDevice = Test-JarvisSyncAuth -WorkspaceId $identity.workspace_id -DeviceId "device-no-autorizado" -SyncSecret $identity.sync_secret
Assert-True (-not $authBadDevice.ok -and $authBadDevice.status -eq 403) "Dispositivo no autorizado no fue rechazado."

$pairing = New-JarvisPairingCode
Assert-True ($pairing.pairing_code -match "^\d{6}$") "El codigo de vinculacion no es corto/numerico."
$paired = Complete-JarvisPairing -PairingCode $pairing.pairing_code -DeviceId "pwa-test-device" -DeviceName "Celular test"
Assert-True (@($paired.linked_devices | Where-Object { $_.device_id -eq "pwa-test-device" }).Count -eq 1) "El dispositivo vinculado no fue registrado."
try {
    Complete-JarvisPairing -PairingCode $pairing.pairing_code -DeviceId "pwa-reuse-test" -DeviceName "Reuso test" | Out-Null
    throw "El codigo de vinculacion pudo reutilizarse."
}
catch {
    Assert-True ($_.Exception.Message -match "No hay un codigo|invalido|expiro") "El reuso del codigo no fallo con un error esperado."
}

$remoteRecord = [pscustomobject]@{
    id = "record-remote-test"
    type = "tarea"
    text = "tarea creada en celular"
    status = "pendiente"
    title = ""
    description = ""
    priority = "media"
    due_date = ""
    tags = @()
    workspace_id = $identity.workspace_id
    device_id = "pwa-test-device"
    revision = 1
    deleted_at = $null
    synced_at = $null
    created_at = "2026-08-09T10:00:00"
    updated_at = "2026-08-09T10:00:00"
}

$remoteChange = [pscustomobject]@{
    change_id = "change-remote-test"
    entity = "records"
    entity_id = $remoteRecord.id
    operation = "create"
    value = $remoteRecord
    workspace_id = $identity.workspace_id
    device_id = "pwa-test-device"
    created_at = "2026-08-09T10:00:01"
}

$results = @(Apply-JarvisSyncChanges -Changes @($remoteChange) -RemoteDeviceId "pwa-test-device")
Assert-True ($results[0].status -eq "accepted") "Cambio remoto valido no fue aceptado."
Assert-True (@(Read-JarvisRecords).Count -eq 1) "El cambio remoto creo duplicados o no fue guardado."

$duplicateResults = @(Apply-JarvisSyncChanges -Changes @($remoteChange) -RemoteDeviceId "pwa-test-device")
Assert-True ($duplicateResults[0].reason -eq "already-seen") "El cambio duplicado no fue detectado."
Assert-True (@(Read-JarvisRecords).Count -eq 1) "El cambio duplicado creo registros extra."

$wrongWorkspaceChange = $remoteChange | ConvertTo-Json -Depth 12 | ConvertFrom-Json
$wrongWorkspaceChange.change_id = "change-wrong-workspace"
$wrongWorkspaceChange.workspace_id = "workspace-otro"
$wrongResults = @(Apply-JarvisSyncChanges -Changes @($wrongWorkspaceChange) -RemoteDeviceId "pwa-test-device")
Assert-True ($wrongResults[0].status -eq "rejected") "Cambio de otro workspace no fue rechazado."

$deleteValue = $remoteRecord | ConvertTo-Json -Depth 12 | ConvertFrom-Json
$deleteValue.deleted_at = "2026-08-09T11:00:00"
$deleteValue.updated_at = "2026-08-09T11:00:00"
$deleteChange = [pscustomobject]@{
    change_id = "change-delete-test"
    entity = "records"
    entity_id = $remoteRecord.id
    operation = "delete"
    value = $deleteValue
    workspace_id = $identity.workspace_id
    device_id = "pwa-test-device"
    created_at = "2026-08-09T11:00:01"
}
$deleteResults = @(Apply-JarvisSyncChanges -Changes @($deleteChange) -RemoteDeviceId "pwa-test-device")
$deletedRecord = @(Read-JarvisRecords)[0]
Assert-True ($deleteResults[0].status -eq "accepted" -and -not [string]::IsNullOrWhiteSpace($deletedRecord.deleted_at)) "Eliminacion logica no se sincronizo."

$olderValue = $deleteValue | ConvertTo-Json -Depth 12 | ConvertFrom-Json
$olderValue.deleted_at = $null
$olderValue.text = "version vieja"
$olderValue.updated_at = "2026-08-09T09:00:00"
$olderChange = [pscustomobject]@{
    change_id = "change-conflict-test"
    entity = "records"
    entity_id = $remoteRecord.id
    operation = "update"
    value = $olderValue
    workspace_id = $identity.workspace_id
    device_id = "pwa-test-device"
    created_at = "2026-08-09T12:00:01"
}
$conflictResults = @(Apply-JarvisSyncChanges -Changes @($olderChange) -RemoteDeviceId "pwa-test-device")
Assert-True ($conflictResults[0].status -eq "conflict") "Conflicto no fue detectado."
Assert-True (@(Read-JarvisSyncConflicts).Count -eq 1) "Conflicto no fue registrado."

Write-Host "Jarvis sync tests OK"
