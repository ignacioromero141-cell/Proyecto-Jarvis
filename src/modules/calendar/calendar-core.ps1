# Reglas principales del modulo Calendario.
# El calendario es la fuente de verdad para fechas visibles en Jarvis.

. (Join-Path $PSScriptRoot "calendar-storage.ps1")

function Get-CalendarSafeText {
    param($Value, [string]$Fallback = "")

    if ($null -eq $Value) { return $Fallback }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $Fallback }
    return $text.Trim()
}

function Get-CalendarLocalDeviceId {
    if (Get-Command Get-JarvisDeviceId -ErrorAction SilentlyContinue) {
        return Get-JarvisDeviceId
    }
    return "notebook-local"
}

function Set-CalendarProperty {
    param($Event, [string]$Name, $Value)

    if ($Event.PSObject.Properties.Name -contains $Name) {
        $Event.$Name = $Value
    }
    else {
        $Event | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Update-CalendarSyncMetadata {
    param($Event)

    $revision = 0
    try { $revision = [int](Get-CalendarSafeText -Value $Event.revision -Fallback "0") } catch { $revision = 0 }
    Set-CalendarProperty -Event $Event -Name "device_id" -Value (Get-CalendarSafeText -Value $Event.device_id -Fallback (Get-CalendarLocalDeviceId))
    Set-CalendarProperty -Event $Event -Name "revision" -Value ($revision + 1)
    Set-CalendarProperty -Event $Event -Name "synced_at" -Value $null
}

function Get-CalendarVisibleEvents {
    return @(Read-CalendarEvents | Where-Object {
        [string]::IsNullOrWhiteSpace((Get-CalendarSafeText -Value $_.deleted_at))
    } | Sort-Object starts_at, title)
}

function Get-CalendarEventById {
    param([string]$Id)

    return Read-CalendarEvents |
        Where-Object { $_.id -eq $Id -and [string]::IsNullOrWhiteSpace((Get-CalendarSafeText -Value $_.deleted_at)) } |
        Select-Object -First 1
}

function Get-CalendarDateTimeText {
    param(
        [string]$Date,
        [string]$Time = ""
    )

    $safeDate = Get-CalendarSafeText -Value $Date
    if ([string]::IsNullOrWhiteSpace($safeDate)) {
        return ""
    }

    $safeTime = Get-CalendarSafeText -Value $Time
    try {
        if ([string]::IsNullOrWhiteSpace($safeTime)) {
            return ([datetime]::Parse($safeDate)).ToString("yyyy-MM-ddT00:00:00")
        }
        return ([datetime]::Parse("$safeDate $safeTime")).ToString("yyyy-MM-ddTHH:mm:ss")
    }
    catch {
        throw "Fecha u hora invalida."
    }
}

function Add-CalendarEvent {
    param(
        [string]$Title,
        [string]$Type = "recordatorio",
        [string]$Date,
        [string]$Time = "",
        [string]$EndsAt = "",
        [bool]$AllDay = $false,
        [string]$Importance = "media",
        [string]$SubjectId = "",
        [string]$LinkedEntityType = "",
        [string]$LinkedEntityId = "",
        [string]$Status = "pendiente",
        [string]$Notes = ""
    )

    $safeTitle = Get-CalendarSafeText -Value $Title
    if ([string]::IsNullOrWhiteSpace($safeTitle)) {
        throw "El evento necesita un titulo."
    }

    $startsAt = Get-CalendarDateTimeText -Date $Date -Time $Time
    if ([string]::IsNullOrWhiteSpace($startsAt)) {
        throw "El evento necesita fecha."
    }

    $now = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    $events = @(Read-CalendarEvents)
    $event = [pscustomobject]@{
        id = "event-$([guid]::NewGuid().ToString("N"))"
        title = $safeTitle
        type = (Get-CalendarSafeText -Value $Type -Fallback "recordatorio")
        starts_at = $startsAt
        ends_at = (Get-CalendarSafeText -Value $EndsAt)
        all_day = $AllDay
        importance = (Get-CalendarSafeText -Value $Importance -Fallback "media")
        subject_id = (Get-CalendarSafeText -Value $SubjectId)
        linked_entity_type = (Get-CalendarSafeText -Value $LinkedEntityType)
        linked_entity_id = (Get-CalendarSafeText -Value $LinkedEntityId)
        status = (Get-CalendarSafeText -Value $Status -Fallback "pendiente")
        notes = (Get-CalendarSafeText -Value $Notes)
        device_id = Get-CalendarLocalDeviceId
        revision = 1
        deleted_at = $null
        synced_at = $null
        created_at = $now
        updated_at = $now
    }

    $events += $event
    Write-CalendarEvents -Events $events -BackupReason "event-add"
    if (Get-Command Add-JarvisSyncChange -ErrorAction SilentlyContinue) {
        Add-JarvisSyncChange -Entity "calendar_events" -EntityId $event.id -Operation "create" -Value $event | Out-Null
    }
    return $event
}

function Update-CalendarEvent {
    param(
        [string]$Id,
        [string]$Title,
        [string]$Type = "recordatorio",
        [string]$Date,
        [string]$Time = "",
        [string]$EndsAt = "",
        [bool]$AllDay = $false,
        [string]$Importance = "media",
        [string]$SubjectId = "",
        [string]$LinkedEntityType = "",
        [string]$LinkedEntityId = "",
        [string]$Status = "pendiente",
        [string]$Notes = ""
    )

    $events = @(Read-CalendarEvents)
    $event = $events | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if (-not $event) {
        throw "No encontre ese evento."
    }

    $startsAt = Get-CalendarDateTimeText -Date $Date -Time $Time
    Set-CalendarProperty -Event $event -Name "title" -Value (Get-CalendarSafeText -Value $Title -Fallback (Get-CalendarSafeText -Value $event.title))
    Set-CalendarProperty -Event $event -Name "type" -Value (Get-CalendarSafeText -Value $Type -Fallback "recordatorio")
    Set-CalendarProperty -Event $event -Name "starts_at" -Value $startsAt
    Set-CalendarProperty -Event $event -Name "ends_at" -Value (Get-CalendarSafeText -Value $EndsAt)
    Set-CalendarProperty -Event $event -Name "all_day" -Value $AllDay
    Set-CalendarProperty -Event $event -Name "importance" -Value (Get-CalendarSafeText -Value $Importance -Fallback "media")
    Set-CalendarProperty -Event $event -Name "subject_id" -Value (Get-CalendarSafeText -Value $SubjectId)
    Set-CalendarProperty -Event $event -Name "linked_entity_type" -Value (Get-CalendarSafeText -Value $LinkedEntityType)
    Set-CalendarProperty -Event $event -Name "linked_entity_id" -Value (Get-CalendarSafeText -Value $LinkedEntityId)
    Set-CalendarProperty -Event $event -Name "status" -Value (Get-CalendarSafeText -Value $Status -Fallback "pendiente")
    Set-CalendarProperty -Event $event -Name "notes" -Value (Get-CalendarSafeText -Value $Notes)
    Set-CalendarProperty -Event $event -Name "updated_at" -Value ((Get-Date).ToString("yyyy-MM-ddTHH:mm:ss"))
    Update-CalendarSyncMetadata -Event $event

    Write-CalendarEvents -Events $events -BackupReason "event-update"
    if (Get-Command Add-JarvisSyncChange -ErrorAction SilentlyContinue) {
        Add-JarvisSyncChange -Entity "calendar_events" -EntityId $event.id -Operation "update" -Value $event | Out-Null
    }
    return $event
}

function Remove-CalendarEvent {
    param([string]$Id)

    $events = @(Read-CalendarEvents)
    $event = $events | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if (-not $event) {
        return
    }

    $now = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    Set-CalendarProperty -Event $event -Name "deleted_at" -Value $now
    Set-CalendarProperty -Event $event -Name "updated_at" -Value $now
    Update-CalendarSyncMetadata -Event $event
    Write-CalendarEvents -Events $events -BackupReason "event-delete"
    if (Get-Command Add-JarvisSyncChange -ErrorAction SilentlyContinue) {
        Add-JarvisSyncChange -Entity "calendar_events" -EntityId $event.id -Operation "delete" -Value $event | Out-Null
    }
}
