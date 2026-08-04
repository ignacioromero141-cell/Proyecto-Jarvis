# Capa de dominio: reglas del asistente para ideas, tareas y recuerdos.
# Aca vive la logica reutilizable por web, escritorio y futuras interfaces.

. (Join-Path $PSScriptRoot "storage.ps1")

function Get-JarvisQuickCapture {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "Escribi algo antes de guardar."
    }

    $cleanText = $Text.Trim()
    $lowerText = $cleanText.ToLowerInvariant()
    $type = "idea"

    if ($lowerText -match "^(tarea|tengo que|debo|hacer|comprar|estudiar|leer)\b") {
        $type = "tarea"
    }
    elseif ($lowerText -match "^(recorda|recordar|recuerdo|dato)\b") {
        $type = "recuerdo"
    }

    $cleanText = $cleanText -replace "(?i)^(idea|tarea|recuerdo|dato)\s*:\s*", ""
    $cleanText = $cleanText -replace "(?i)^(recorda que|recordar que|recorda|recordar)\s+", ""
    $cleanText = $cleanText -replace "(?i)^(tengo que|debo)\s+", ""

    return [pscustomobject]@{
        type = $type
        text = $cleanText.Trim()
    }
}

function Add-JarvisRecord {
    param(
        [string]$Type,
        [string]$Text,
        [string]$Title = "",
        [string]$Description = "",
        [string]$Priority = "",
        [string]$DueDate = "",
        $Tags = ""
    )

    $safeType = Get-JarvisSafeText -Value $Type -Fallback "idea"
    if (@("idea", "tarea", "recuerdo") -notcontains $safeType) {
        $safeType = "idea"
    }
    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "Escribi algo antes de guardar."
    }

    $records = @(Read-JarvisRecords)
    $now = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    $record = [pscustomobject]@{
        id = [guid]::NewGuid().ToString("N")
        type = $safeType
        text = $Text.Trim()
        status = if ($safeType -eq "tarea") { "pendiente" } else { "activo" }
        title = (Get-JarvisSafeText -Value $Title)
        description = (Get-JarvisSafeText -Value $Description)
        priority = (Get-JarvisSafePriority -Value $Priority)
        due_date = (Get-JarvisSafeDateOnly -Value $DueDate)
        tags = @(Get-JarvisTags -Value $Tags)
        device_id = Get-JarvisDeviceId
        revision = 1
        deleted_at = $null
        synced_at = $null
        created_at = $now
        updated_at = $now
    }

    $records += $record
    Write-JarvisRecords -Records $records -BackupReason "record-add"
    return $record
}

function Get-JarvisSafePriority {
    param($Value)

    $priority = (Get-JarvisSafeText -Value $Value).ToLowerInvariant()
    if (@("baja", "media", "alta") -contains $priority) {
        return $priority
    }

    return ""
}

function Get-JarvisSafeDateOnly {
    param($Value)

    $dateText = Get-JarvisSafeText -Value $Value
    if ([string]::IsNullOrWhiteSpace($dateText)) {
        return ""
    }

    try {
        return ([datetime]::Parse($dateText)).ToString("yyyy-MM-dd")
    }
    catch {
        return ""
    }
}

function Get-JarvisTags {
    param($Value)

    if ($null -eq $Value) {
        return @()
    }

    if ($Value -is [array]) {
        return @($Value | ForEach-Object { Get-JarvisSafeText -Value $_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    }

    $text = Get-JarvisSafeText -Value $Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return @()
    }

    return @($text.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
}

function Set-JarvisRecordProperty {
    param(
        $Record,
        [string]$Name,
        $Value
    )

    if ($Record.PSObject.Properties.Name -contains $Name) {
        $Record.$Name = $Value
    }
    else {
        $Record | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Get-JarvisVisibleRecords {
    return @(Read-JarvisRecords | Where-Object {
        [string]::IsNullOrWhiteSpace((Get-JarvisSafeText -Value $_.deleted_at))
    })
}

function Update-JarvisRecordSyncMetadata {
    param($Record)

    $revision = 0
    try {
        $revision = [int](Get-JarvisSafeText -Value $Record.revision -Fallback "0")
    }
    catch {
        $revision = 0
    }

    Set-JarvisRecordProperty -Record $Record -Name "device_id" -Value (Get-JarvisSafeText -Value $Record.device_id -Fallback (Get-JarvisDeviceId))
    Set-JarvisRecordProperty -Record $Record -Name "revision" -Value ($revision + 1)
    Set-JarvisRecordProperty -Record $Record -Name "synced_at" -Value $null
}

function Update-JarvisRecord {
    param(
        [string]$Id,
        [string]$Type,
        [string]$Text,
        [string]$Title = "",
        [string]$Description = "",
        [string]$Priority = "",
        [string]$DueDate = "",
        $Tags = ""
    )

    $records = @(Read-JarvisRecords)
    $record = $records | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if (-not $record) {
        throw "No encontre un registro con ese codigo."
    }

    $safeType = Get-JarvisSafeText -Value $Type -Fallback (Get-JarvisSafeText -Value $record.type -Fallback "idea")
    if (@("idea", "tarea", "recuerdo") -notcontains $safeType) {
        $safeType = Get-JarvisSafeText -Value $record.type -Fallback "idea"
    }
    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "El contenido no puede estar vacio."
    }

    Set-JarvisRecordProperty -Record $record -Name "type" -Value $safeType
    Set-JarvisRecordProperty -Record $record -Name "text" -Value $Text.Trim()
    Set-JarvisRecordProperty -Record $record -Name "title" -Value (Get-JarvisSafeText -Value $Title)
    Set-JarvisRecordProperty -Record $record -Name "description" -Value (Get-JarvisSafeText -Value $Description)
    Set-JarvisRecordProperty -Record $record -Name "priority" -Value (Get-JarvisSafePriority -Value $Priority)
    Set-JarvisRecordProperty -Record $record -Name "due_date" -Value (Get-JarvisSafeDateOnly -Value $DueDate)
    Set-JarvisRecordProperty -Record $record -Name "tags" -Value @(Get-JarvisTags -Value $Tags)
    Update-JarvisRecordSyncMetadata -Record $record

    if ($safeType -eq "tarea") {
        $status = Get-JarvisSafeText -Value $record.status -Fallback "pendiente"
        if (@("pendiente", "completada") -notcontains $status) {
            $status = "pendiente"
        }
        Set-JarvisRecordProperty -Record $record -Name "status" -Value $status
    }
    else {
        Set-JarvisRecordProperty -Record $record -Name "status" -Value "activo"
    }

    Set-JarvisRecordProperty -Record $record -Name "updated_at" -Value ((Get-Date).ToString("yyyy-MM-ddTHH:mm:ss"))
    Write-JarvisRecords -Records $records -BackupReason "record-update"
    return $record
}

function Set-JarvisTaskStatus {
    param(
        [string]$Id,
        [string]$Status
    )

    $safeStatus = (Get-JarvisSafeText -Value $Status -Fallback "pendiente").ToLowerInvariant()
    if (@("pendiente", "completada") -notcontains $safeStatus) {
        throw "Estado de tarea invalido."
    }

    $records = @(Read-JarvisRecords)
    $record = $records | Where-Object { $_.id -eq $Id -and $_.type -eq "tarea" } | Select-Object -First 1
    if (-not $record) {
        throw "No encontre una tarea con ese codigo."
    }

    Set-JarvisRecordProperty -Record $record -Name "status" -Value $safeStatus
    Set-JarvisRecordProperty -Record $record -Name "updated_at" -Value ((Get-Date).ToString("yyyy-MM-ddTHH:mm:ss"))
    Update-JarvisRecordSyncMetadata -Record $record
    Write-JarvisRecords -Records $records -BackupReason "task-status"
    return $record
}

function Complete-JarvisTask {
    param([string]$Id)

    Set-JarvisTaskStatus -Id $Id -Status "completada" | Out-Null
}

function Remove-JarvisRecord {
    param([string]$Id)

    $records = @(Read-JarvisRecords)
    $record = $records | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if (-not $record) {
        return
    }

    $now = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    Set-JarvisRecordProperty -Record $record -Name "deleted_at" -Value $now
    Set-JarvisRecordProperty -Record $record -Name "updated_at" -Value $now
    Update-JarvisRecordSyncMetadata -Record $record
    Write-JarvisRecords -Records $records -BackupReason "record-delete"
}

function Get-JarvisDashboardSummary {
    $records = @(Get-JarvisVisibleRecords)
    $pendingTasks = @($records | Where-Object {
        (Get-JarvisSafeText -Value $_.type) -eq "tarea" -and
        (Get-JarvisSafeText -Value $_.status -Fallback "pendiente") -eq "pendiente"
    })
    $todayRecords = @($records | Where-Object { Test-JarvisDateIsToday -Value $_.created_at })

    return [pscustomobject]@{
        total = $records.Count
        pending_tasks = $pendingTasks.Count
        today_records = $todayRecords.Count
        ideas = @($records | Where-Object { (Get-JarvisSafeText -Value $_.type) -eq "idea" }).Count
        memories = @($records | Where-Object { (Get-JarvisSafeText -Value $_.type) -eq "recuerdo" }).Count
    }
}
