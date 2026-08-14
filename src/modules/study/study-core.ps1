# Reglas principales del modulo Estudio.
# Las materias son entidades del modulo Estudio, no modulos independientes.

. (Join-Path $PSScriptRoot "study-storage.ps1")

function Get-StudySafeText {
    param($Value, [string]$Fallback = "")

    if ($null -eq $Value) { return $Fallback }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $Fallback }
    return $text.Trim()
}

function Get-StudyLocalDeviceId {
    if (Get-Command Get-JarvisDeviceId -ErrorAction SilentlyContinue) {
        return Get-JarvisDeviceId
    }
    return "notebook-local"
}

function Set-StudyProperty {
    param($Item, [string]$Name, $Value)

    if ($Item.PSObject.Properties.Name -contains $Name) {
        $Item.$Name = $Value
    }
    else {
        $Item | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Update-StudySyncMetadata {
    param($Item)

    $revision = 0
    try { $revision = [int](Get-StudySafeText -Value $Item.revision -Fallback "0") } catch { $revision = 0 }
    Set-StudyProperty -Item $Item -Name "device_id" -Value (Get-StudySafeText -Value $Item.device_id -Fallback (Get-StudyLocalDeviceId))
    Set-StudyProperty -Item $Item -Name "revision" -Value ($revision + 1)
    Set-StudyProperty -Item $Item -Name "synced_at" -Value $null
}

function Add-StudySyncChange {
    param([string]$Entity, [string]$EntityId, [string]$Operation, $Value)

    if (Get-Command Add-JarvisSyncChange -ErrorAction SilentlyContinue) {
        Add-JarvisSyncChange -Entity $Entity -EntityId $EntityId -Operation $Operation -Value $Value | Out-Null
    }
}

function Get-StudyVisible {
    param([array]$Items)

    return @($Items | Where-Object {
        [string]::IsNullOrWhiteSpace((Get-StudySafeText -Value $_.deleted_at))
    })
}

function Get-StudyVisibleSubjects { return Get-StudyVisible -Items (Read-StudySubjects) }
function Get-StudyVisibleTopics { return Get-StudyVisible -Items (Read-StudyTopics) }
function Get-StudyVisibleEvaluations { return Get-StudyVisible -Items (Read-StudyEvaluations) }
function Get-StudyVisibleAssignments { return Get-StudyVisible -Items (Read-StudyAssignments) }
function Get-StudyVisibleNotes { return Get-StudyVisible -Items (Read-StudyNotes) }
function Get-StudyVisibleSchedules { return Get-StudyVisible -Items (Read-StudySchedules) }

function Get-StudySubjectById {
    param([string]$Id)

    return Get-StudyVisibleSubjects | Where-Object { $_.id -eq $Id } | Select-Object -First 1
}

function Test-StudySubjectStatus {
    param([string]$Status)

    return @("cursando", "final_pendiente", "aprobada", "recursando", "archivada") -contains $Status
}

function Add-StudySubject {
    param(
        [string]$Name,
        [string]$Status = "cursando",
        [string]$Year = "",
        [string]$Term = "",
        [string]$Professors = "",
        [string]$Classroom = "",
        [string]$EvaluationMethod = "",
        [string]$ScheduleNotes = "",
        [string]$Color = "#8B5CF6"
    )

    $safeName = Get-StudySafeText -Value $Name
    if ([string]::IsNullOrWhiteSpace($safeName)) {
        throw "La materia necesita un nombre."
    }
    $safeStatus = Get-StudySafeText -Value $Status -Fallback "cursando"
    if (-not (Test-StudySubjectStatus -Status $safeStatus)) {
        throw "Estado de materia invalido."
    }

    $now = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    $subjects = @(Read-StudySubjects)
    $subject = [pscustomobject]@{
        id = "subject-$([guid]::NewGuid().ToString("N"))"
        name = $safeName
        status = $safeStatus
        year = (Get-StudySafeText -Value $Year)
        term = (Get-StudySafeText -Value $Term)
        professors = (Get-StudySafeText -Value $Professors)
        classroom = (Get-StudySafeText -Value $Classroom)
        evaluation_method = (Get-StudySafeText -Value $EvaluationMethod)
        schedule_notes = (Get-StudySafeText -Value $ScheduleNotes)
        color = (Get-StudySafeText -Value $Color -Fallback "#8B5CF6")
        device_id = Get-StudyLocalDeviceId
        revision = 1
        deleted_at = $null
        archived_at = $null
        synced_at = $null
        created_at = $now
        updated_at = $now
    }

    $subjects += $subject
    Write-StudySubjects -Subjects $subjects -BackupReason "subject-add"
    Add-StudySyncChange -Entity "study_subjects" -EntityId $subject.id -Operation "create" -Value $subject
    return $subject
}

function Update-StudySubject {
    param(
        [string]$Id,
        [string]$Name,
        [string]$Status = "cursando",
        [string]$Year = "",
        [string]$Term = "",
        [string]$Professors = "",
        [string]$Classroom = "",
        [string]$EvaluationMethod = "",
        [string]$ScheduleNotes = "",
        [string]$Color = "#8B5CF6"
    )

    $subjects = @(Read-StudySubjects)
    $subject = $subjects | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if (-not $subject) { throw "No encontre esa materia." }

    $safeName = Get-StudySafeText -Value $Name -Fallback (Get-StudySafeText -Value $subject.name)
    $safeStatus = Get-StudySafeText -Value $Status -Fallback "cursando"
    if (-not (Test-StudySubjectStatus -Status $safeStatus)) {
        throw "Estado de materia invalido."
    }

    $now = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    Set-StudyProperty -Item $subject -Name "name" -Value $safeName
    Set-StudyProperty -Item $subject -Name "status" -Value $safeStatus
    Set-StudyProperty -Item $subject -Name "year" -Value (Get-StudySafeText -Value $Year)
    Set-StudyProperty -Item $subject -Name "term" -Value (Get-StudySafeText -Value $Term)
    Set-StudyProperty -Item $subject -Name "professors" -Value (Get-StudySafeText -Value $Professors)
    Set-StudyProperty -Item $subject -Name "classroom" -Value (Get-StudySafeText -Value $Classroom)
    Set-StudyProperty -Item $subject -Name "evaluation_method" -Value (Get-StudySafeText -Value $EvaluationMethod)
    Set-StudyProperty -Item $subject -Name "schedule_notes" -Value (Get-StudySafeText -Value $ScheduleNotes)
    Set-StudyProperty -Item $subject -Name "color" -Value (Get-StudySafeText -Value $Color -Fallback "#8B5CF6")
    Set-StudyProperty -Item $subject -Name "archived_at" -Value $(if ($safeStatus -eq "archivada") { $now } else { $null })
    Set-StudyProperty -Item $subject -Name "updated_at" -Value $now
    Update-StudySyncMetadata -Item $subject

    Write-StudySubjects -Subjects $subjects -BackupReason "subject-update"
    Add-StudySyncChange -Entity "study_subjects" -EntityId $subject.id -Operation "update" -Value $subject
    return $subject
}

function Remove-StudySubject {
    param([string]$Id)

    $subjects = @(Read-StudySubjects)
    $subject = $subjects | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if (-not $subject) { return }

    $now = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    Set-StudyProperty -Item $subject -Name "status" -Value "archivada"
    Set-StudyProperty -Item $subject -Name "archived_at" -Value $now
    Set-StudyProperty -Item $subject -Name "updated_at" -Value $now
    Update-StudySyncMetadata -Item $subject

    Write-StudySubjects -Subjects $subjects -BackupReason "subject-archive"
    Add-StudySyncChange -Entity "study_subjects" -EntityId $subject.id -Operation "archive" -Value $subject
}

function Add-StudyTopic {
    param(
        [string]$SubjectId,
        [string]$Title,
        [string]$Status = "pendiente",
        [int]$Progress = 0,
        [string]$Notes = ""
    )

    if (-not (Get-StudySubjectById -Id $SubjectId)) { throw "Materia invalida." }
    $safeTitle = Get-StudySafeText -Value $Title
    if ([string]::IsNullOrWhiteSpace($safeTitle)) { throw "El tema necesita un titulo." }

    $now = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    $topics = @(Read-StudyTopics)
    $topic = [pscustomobject]@{
        id = "topic-$([guid]::NewGuid().ToString("N"))"
        subject_id = $SubjectId
        title = $safeTitle
        status = (Get-StudySafeText -Value $Status -Fallback "pendiente")
        progress = [math]::Max(0, [math]::Min(100, $Progress))
        notes = (Get-StudySafeText -Value $Notes)
        device_id = Get-StudyLocalDeviceId
        revision = 1
        deleted_at = $null
        synced_at = $null
        created_at = $now
        updated_at = $now
    }
    $topics += $topic
    Write-StudyTopics -Topics $topics -BackupReason "topic-add"
    Add-StudySyncChange -Entity "study_topics" -EntityId $topic.id -Operation "create" -Value $topic
    return $topic
}

function Update-StudyTopic {
    param([string]$Id, [string]$Title, [string]$Status = "pendiente", [int]$Progress = 0, [string]$Notes = "")

    $topics = @(Read-StudyTopics)
    $topic = $topics | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if (-not $topic) { throw "No encontre ese tema." }

    Set-StudyProperty -Item $topic -Name "title" -Value (Get-StudySafeText -Value $Title -Fallback (Get-StudySafeText -Value $topic.title))
    Set-StudyProperty -Item $topic -Name "status" -Value (Get-StudySafeText -Value $Status -Fallback "pendiente")
    Set-StudyProperty -Item $topic -Name "progress" -Value ([math]::Max(0, [math]::Min(100, $Progress)))
    Set-StudyProperty -Item $topic -Name "notes" -Value (Get-StudySafeText -Value $Notes)
    Set-StudyProperty -Item $topic -Name "updated_at" -Value ((Get-Date).ToString("yyyy-MM-ddTHH:mm:ss"))
    Update-StudySyncMetadata -Item $topic
    Write-StudyTopics -Topics $topics -BackupReason "topic-update"
    Add-StudySyncChange -Entity "study_topics" -EntityId $topic.id -Operation "update" -Value $topic
    return $topic
}

function Remove-StudyEntityItem {
    param(
        [string]$Id,
        [string]$Entity,
        [scriptblock]$Read,
        [scriptblock]$Write,
        [string]$BackupReason = "delete"
    )

    $items = @(& $Read)
    $item = $items | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if (-not $item) { return }
    $now = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    Set-StudyProperty -Item $item -Name "deleted_at" -Value $now
    Set-StudyProperty -Item $item -Name "updated_at" -Value $now
    Update-StudySyncMetadata -Item $item
    & $Write $items $BackupReason
    Add-StudySyncChange -Entity $Entity -EntityId $item.id -Operation "delete" -Value $item
}

function Remove-StudyTopic {
    param([string]$Id)
    Remove-StudyEntityItem -Id $Id -Entity "study_topics" -Read { Read-StudyTopics } -Write { param($Items, $Reason) Write-StudyTopics -Topics $Items -BackupReason $Reason } -BackupReason "topic-delete"
}

function Add-StudyCalendarBackedItem {
    param(
        [string]$Collection,
        [string]$SubjectId,
        [string]$Title,
        [string]$Type,
        [string]$Date,
        [string]$Time,
        [string]$Importance,
        [string]$Status,
        [int]$Progress,
        [string]$Notes
    )

    $subject = Get-StudySubjectById -Id $SubjectId
    if (-not $subject) { throw "Materia invalida." }
    $safeTitle = Get-StudySafeText -Value $Title
    if ([string]::IsNullOrWhiteSpace($safeTitle)) { throw "Necesita un titulo." }

    $now = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    $idPrefix = if ($Collection -eq "evaluation") { "evaluation-" } else { "assignment-" }
    $entity = if ($Collection -eq "evaluation") { "study_evaluations" } else { "study_assignments" }
    $linkedType = if ($Collection -eq "evaluation") { "study_evaluation" } else { "study_assignment" }
    $itemId = "$idPrefix$([guid]::NewGuid().ToString("N"))"
    $eventTitle = "$(Get-StudySafeText -Value $subject.name): $safeTitle"
    $eventType = if ($Collection -eq "evaluation") { (Get-StudySafeText -Value $Type -Fallback "parcial") } else { "tp" }

    $event = Add-CalendarEvent -Title $eventTitle -Type $eventType -Date $Date -Time $Time -Importance $Importance -SubjectId $SubjectId -LinkedEntityType $linkedType -LinkedEntityId $itemId -Status $Status -Notes $Notes
    $item = [pscustomobject]@{
        id = $itemId
        subject_id = $SubjectId
        title = $safeTitle
        type = (Get-StudySafeText -Value $Type -Fallback $(if ($Collection -eq "evaluation") { "parcial" } else { "tp" }))
        calendar_event_id = $event.id
        topic_ids = @()
        status = (Get-StudySafeText -Value $Status -Fallback "pendiente")
        progress = [math]::Max(0, [math]::Min(100, $Progress))
        notes = (Get-StudySafeText -Value $Notes)
        device_id = Get-StudyLocalDeviceId
        revision = 1
        deleted_at = $null
        synced_at = $null
        created_at = $now
        updated_at = $now
    }

    if ($Collection -eq "evaluation") {
        $items = @(Read-StudyEvaluations)
        $items += $item
        Write-StudyEvaluations -Evaluations $items -BackupReason "evaluation-add"
    }
    else {
        $items = @(Read-StudyAssignments)
        $items += $item
        Write-StudyAssignments -Assignments $items -BackupReason "assignment-add"
    }

    Add-StudySyncChange -Entity $entity -EntityId $item.id -Operation "create" -Value $item
    return $item
}

function Update-StudyCalendarBackedItem {
    param(
        [string]$Collection,
        [string]$Id,
        [string]$Title,
        [string]$Type,
        [string]$Date,
        [string]$Time,
        [string]$Importance,
        [string]$Status,
        [int]$Progress,
        [string]$Notes
    )

    $items = if ($Collection -eq "evaluation") { @(Read-StudyEvaluations) } else { @(Read-StudyAssignments) }
    $item = $items | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if (-not $item) { throw "No encontre ese registro academico." }

    $subject = Get-StudySubjectById -Id $item.subject_id
    if (-not $subject) { throw "Materia invalida." }

    $safeTitle = Get-StudySafeText -Value $Title -Fallback (Get-StudySafeText -Value $item.title)
    $eventType = if ($Collection -eq "evaluation") { (Get-StudySafeText -Value $Type -Fallback "parcial") } else { "tp" }
    $linkedType = if ($Collection -eq "evaluation") { "study_evaluation" } else { "study_assignment" }
    $eventTitle = "$(Get-StudySafeText -Value $subject.name): $safeTitle"
    $eventId = Get-StudySafeText -Value $item.calendar_event_id

    if ([string]::IsNullOrWhiteSpace($eventId) -or -not (Get-CalendarEventById -Id $eventId)) {
        $event = Add-CalendarEvent -Title $eventTitle -Type $eventType -Date $Date -Time $Time -Importance $Importance -SubjectId $item.subject_id -LinkedEntityType $linkedType -LinkedEntityId $item.id -Status $Status -Notes $Notes
        $eventId = $event.id
    }
    else {
        Update-CalendarEvent -Id $eventId -Title $eventTitle -Type $eventType -Date $Date -Time $Time -Importance $Importance -SubjectId $item.subject_id -LinkedEntityType $linkedType -LinkedEntityId $item.id -Status $Status -Notes $Notes | Out-Null
    }

    Set-StudyProperty -Item $item -Name "title" -Value $safeTitle
    Set-StudyProperty -Item $item -Name "type" -Value (Get-StudySafeText -Value $Type -Fallback $(if ($Collection -eq "evaluation") { "parcial" } else { "tp" }))
    Set-StudyProperty -Item $item -Name "calendar_event_id" -Value $eventId
    Set-StudyProperty -Item $item -Name "status" -Value (Get-StudySafeText -Value $Status -Fallback "pendiente")
    Set-StudyProperty -Item $item -Name "progress" -Value ([math]::Max(0, [math]::Min(100, $Progress)))
    Set-StudyProperty -Item $item -Name "notes" -Value (Get-StudySafeText -Value $Notes)
    Set-StudyProperty -Item $item -Name "updated_at" -Value ((Get-Date).ToString("yyyy-MM-ddTHH:mm:ss"))
    Update-StudySyncMetadata -Item $item

    $entity = if ($Collection -eq "evaluation") { "study_evaluations" } else { "study_assignments" }
    if ($Collection -eq "evaluation") {
        Write-StudyEvaluations -Evaluations $items -BackupReason "evaluation-update"
    }
    else {
        Write-StudyAssignments -Assignments $items -BackupReason "assignment-update"
    }
    Add-StudySyncChange -Entity $entity -EntityId $item.id -Operation "update" -Value $item
    return $item
}

function Add-StudyEvaluation {
    param([string]$SubjectId, [string]$Title, [string]$Type = "parcial", [string]$Date, [string]$Time = "", [string]$Importance = "alta", [string]$Status = "pendiente", [int]$Progress = 0, [string]$Notes = "")
    return Add-StudyCalendarBackedItem -Collection "evaluation" -SubjectId $SubjectId -Title $Title -Type $Type -Date $Date -Time $Time -Importance $Importance -Status $Status -Progress $Progress -Notes $Notes
}

function Update-StudyEvaluation {
    param([string]$Id, [string]$Title, [string]$Type = "parcial", [string]$Date, [string]$Time = "", [string]$Importance = "alta", [string]$Status = "pendiente", [int]$Progress = 0, [string]$Notes = "")
    return Update-StudyCalendarBackedItem -Collection "evaluation" -Id $Id -Title $Title -Type $Type -Date $Date -Time $Time -Importance $Importance -Status $Status -Progress $Progress -Notes $Notes
}

function Remove-StudyEvaluation {
    param([string]$Id)
    $item = Read-StudyEvaluations | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if ($item -and (Get-StudySafeText -Value $item.calendar_event_id)) {
        Remove-CalendarEvent -Id $item.calendar_event_id
    }
    Remove-StudyEntityItem -Id $Id -Entity "study_evaluations" -Read { Read-StudyEvaluations } -Write { param($Items, $Reason) Write-StudyEvaluations -Evaluations $Items -BackupReason $Reason } -BackupReason "evaluation-delete"
}

function Add-StudyAssignment {
    param([string]$SubjectId, [string]$Title, [string]$Date, [string]$Time = "", [string]$Importance = "media", [string]$Status = "pendiente", [int]$Progress = 0, [string]$Notes = "")
    return Add-StudyCalendarBackedItem -Collection "assignment" -SubjectId $SubjectId -Title $Title -Type "tp" -Date $Date -Time $Time -Importance $Importance -Status $Status -Progress $Progress -Notes $Notes
}

function Update-StudyAssignment {
    param([string]$Id, [string]$Title, [string]$Date, [string]$Time = "", [string]$Importance = "media", [string]$Status = "pendiente", [int]$Progress = 0, [string]$Notes = "")
    return Update-StudyCalendarBackedItem -Collection "assignment" -Id $Id -Title $Title -Type "tp" -Date $Date -Time $Time -Importance $Importance -Status $Status -Progress $Progress -Notes $Notes
}

function Remove-StudyAssignment {
    param([string]$Id)
    $item = Read-StudyAssignments | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if ($item -and (Get-StudySafeText -Value $item.calendar_event_id)) {
        Remove-CalendarEvent -Id $item.calendar_event_id
    }
    Remove-StudyEntityItem -Id $Id -Entity "study_assignments" -Read { Read-StudyAssignments } -Write { param($Items, $Reason) Write-StudyAssignments -Assignments $Items -BackupReason $Reason } -BackupReason "assignment-delete"
}

function Add-StudyNote {
    param([string]$SubjectId, [string]$Title, [string]$Text, [string]$LinkedEntityType = "", [string]$LinkedEntityId = "")

    if (-not (Get-StudySubjectById -Id $SubjectId)) { throw "Materia invalida." }
    $safeText = Get-StudySafeText -Value $Text
    if ([string]::IsNullOrWhiteSpace($safeText)) { throw "La nota no puede estar vacia." }

    $now = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    $notes = @(Read-StudyNotes)
    $note = [pscustomobject]@{
        id = "note-$([guid]::NewGuid().ToString("N"))"
        subject_id = $SubjectId
        title = (Get-StudySafeText -Value $Title -Fallback "Nota")
        text = $safeText
        linked_entity_type = (Get-StudySafeText -Value $LinkedEntityType)
        linked_entity_id = (Get-StudySafeText -Value $LinkedEntityId)
        device_id = Get-StudyLocalDeviceId
        revision = 1
        deleted_at = $null
        synced_at = $null
        created_at = $now
        updated_at = $now
    }
    $notes += $note
    Write-StudyNotes -Notes $notes -BackupReason "note-add"
    Add-StudySyncChange -Entity "study_notes" -EntityId $note.id -Operation "create" -Value $note
    return $note
}

function Update-StudyNote {
    param([string]$Id, [string]$Title, [string]$Text)

    $notes = @(Read-StudyNotes)
    $note = $notes | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if (-not $note) { throw "No encontre esa nota." }
    Set-StudyProperty -Item $note -Name "title" -Value (Get-StudySafeText -Value $Title -Fallback (Get-StudySafeText -Value $note.title))
    Set-StudyProperty -Item $note -Name "text" -Value (Get-StudySafeText -Value $Text)
    Set-StudyProperty -Item $note -Name "updated_at" -Value ((Get-Date).ToString("yyyy-MM-ddTHH:mm:ss"))
    Update-StudySyncMetadata -Item $note
    Write-StudyNotes -Notes $notes -BackupReason "note-update"
    Add-StudySyncChange -Entity "study_notes" -EntityId $note.id -Operation "update" -Value $note
    return $note
}

function Remove-StudyNote {
    param([string]$Id)
    Remove-StudyEntityItem -Id $Id -Entity "study_notes" -Read { Read-StudyNotes } -Write { param($Items, $Reason) Write-StudyNotes -Notes $Items -BackupReason $Reason } -BackupReason "note-delete"
}

function Add-StudySchedule {
    param([string]$SubjectId, [string]$DayOfWeek, [string]$StartsAt, [string]$EndsAt = "", [string]$Location = "", [string]$Notes = "")

    if (-not (Get-StudySubjectById -Id $SubjectId)) { throw "Materia invalida." }
    $safeDay = Get-StudySafeText -Value $DayOfWeek
    $safeStart = Get-StudySafeText -Value $StartsAt
    if ([string]::IsNullOrWhiteSpace($safeDay) -or [string]::IsNullOrWhiteSpace($safeStart)) {
        throw "El horario necesita dia y hora de inicio."
    }

    $now = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    $schedules = @(Read-StudySchedules)
    $schedule = [pscustomobject]@{
        id = "schedule-$([guid]::NewGuid().ToString("N"))"
        subject_id = $SubjectId
        day_of_week = $safeDay
        starts_at = $safeStart
        ends_at = (Get-StudySafeText -Value $EndsAt)
        location = (Get-StudySafeText -Value $Location)
        notes = (Get-StudySafeText -Value $Notes)
        device_id = Get-StudyLocalDeviceId
        revision = 1
        deleted_at = $null
        synced_at = $null
        created_at = $now
        updated_at = $now
    }
    $schedules += $schedule
    Write-StudySchedules -Schedules $schedules -BackupReason "schedule-add"
    Add-StudySyncChange -Entity "study_schedules" -EntityId $schedule.id -Operation "create" -Value $schedule
    return $schedule
}

function Remove-StudySchedule {
    param([string]$Id)
    Remove-StudyEntityItem -Id $Id -Entity "study_schedules" -Read { Read-StudySchedules } -Write { param($Items, $Reason) Write-StudySchedules -Schedules $Items -BackupReason $Reason } -BackupReason "schedule-delete"
}

function Get-StudySummary {
    return [pscustomobject]@{
        subjects = @(Get-StudyVisibleSubjects)
        topics = @(Get-StudyVisibleTopics)
        evaluations = @(Get-StudyVisibleEvaluations)
        assignments = @(Get-StudyVisibleAssignments)
        notes = @(Get-StudyVisibleNotes)
        schedules = @(Get-StudyVisibleSchedules)
    }
}
