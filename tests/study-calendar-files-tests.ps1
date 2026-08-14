$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "..\src\web\server.ps1")

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) {
        throw $Message
    }
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "jarvis-study-calendar-test-$([guid]::NewGuid().ToString("N"))"
New-Item -ItemType Directory -Path $tempRoot | Out-Null

try {
    Initialize-JarvisStorage -ProjectRoot $tempRoot
    Initialize-FinanceStorage -ProjectRoot $tempRoot
    Initialize-CalendarStorage -ProjectRoot $tempRoot
    Initialize-StudyStorage -ProjectRoot $tempRoot
    Initialize-FilesStorage -ProjectRoot $tempRoot
    Initialize-JarvisSyncStorage

    $subject = Add-StudySubject -Name "Analisis Matematico" -Status "cursando" -Year "2026" -Term "1C"
    Assert-True ($subject.id -like "subject-*") "No se creo la materia."

    $topic = Add-StudyTopic -SubjectId $subject.id -Title "Integrales" -Status "pendiente" -Progress 10
    Assert-True ($topic.subject_id -eq $subject.id) "El tema no quedo asociado a la materia."

    $evaluationDate = (Get-Date).AddDays(10).ToString("yyyy-MM-dd")
    $updatedEvaluationDate = (Get-Date).AddDays(12).ToString("yyyy-MM-dd")
    $assignmentDate = (Get-Date).AddDays(14).ToString("yyyy-MM-dd")

    $evaluation = Add-StudyEvaluation -SubjectId $subject.id -Title "Parcial 1" -Type "parcial" -Date $evaluationDate -Time "08:00" -Progress 0
    Assert-True (-not [string]::IsNullOrWhiteSpace($evaluation.calendar_event_id)) "La evaluacion no creo evento de calendario."
    $events = @(Get-CalendarVisibleEvents)
    Assert-True ($events.Count -eq 1) "La evaluacion genero una cantidad incorrecta de eventos."
    Assert-True ($events[0].linked_entity_id -eq $evaluation.id) "El evento no apunta a la evaluacion."

    Update-CalendarEvent -Id $evaluation.calendar_event_id -Title $events[0].title -Type $events[0].type -Date $updatedEvaluationDate -Time "09:30" -Importance "alta" -SubjectId $subject.id -LinkedEntityType "study_evaluation" -LinkedEntityId $evaluation.id -Status "pendiente" -Notes "" | Out-Null
    $updatedEvent = Get-CalendarEventById -Id $evaluation.calendar_event_id
    Assert-True ($updatedEvent.starts_at -eq "$updatedEvaluationDate`T09:30:00") "Editar desde calendario no actualizo el mismo evento."
    Assert-True (@(Get-CalendarVisibleEvents).Count -eq 1) "Editar fecha desde calendario duplico el evento."

    $assignment = Add-StudyAssignment -SubjectId $subject.id -Title "TP 1" -Date $assignmentDate
    Assert-True (-not [string]::IsNullOrWhiteSpace($assignment.calendar_event_id)) "El TP no creo evento."
    Assert-True (@(Get-CalendarVisibleEvents).Count -eq 2) "El TP no quedo en calendario."

    $note = Add-StudyNote -SubjectId $subject.id -Title "Idea" -Text "Repasar sustitucion."
    Assert-True ($note.text -eq "Repasar sustitucion.") "No se guardo la nota."

    $schedule = Add-StudySchedule -SubjectId $subject.id -DayOfWeek "monday" -StartsAt "08:00" -EndsAt "10:00" -Location "Aula 3"
    Assert-True ($schedule.day_of_week -eq "monday") "No se guardo el horario."

    $folder = Join-Path $tempRoot "materia-files"
    New-Item -ItemType Directory -Path $folder | Out-Null
    $file = Join-Path $folder "Final-2025.pdf"
    "contenido de prueba" | Set-Content -LiteralPath $file -Encoding UTF8
    $root = Add-FileRoot -Path $folder -Label "Analisis"
    $scan = Scan-FileRoot -RootId $root.id -TargetType "subject" -TargetId $subject.id
    Assert-True ($scan.scanned -eq 1) "El escaneo no detecto el archivo."
    Assert-True (@(Get-FileVisibleAssets).Count -eq 1) "No se creo metadata del archivo."
    Assert-True (@(Get-FileVisibleLinks | Where-Object { $_.target_id -eq $subject.id }).Count -eq 1) "No se vinculo el archivo a la materia."

    $insights = @(Get-JarvisInsights)
    Assert-True ($insights.Count -gt 0) "No se generaron insights."

    Ensure-JarvisBaselineSyncChanges
    $changes = @(Get-JarvisSyncChangesSince -Since "")
    foreach ($entity in @("study_subjects", "study_topics", "study_evaluations", "study_assignments", "study_notes", "study_schedules", "calendar_events", "file_assets", "file_links")) {
        Assert-True (@($changes | Where-Object { $_.entity -eq $entity }).Count -gt 0) "Falta la entidad $entity en sync."
    }

    Write-Host "Jarvis study calendar files tests OK"
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
