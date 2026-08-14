# Avisos proactivos reutilizables.
# El Dashboard consume esta capa; la logica no queda embebida en la pantalla.

function Get-JarvisInsightSafeText {
    param($Value, [string]$Fallback = "")
    if ($null -eq $Value) { return $Fallback }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $Fallback }
    return $text.Trim()
}

function ConvertTo-JarvisInsightDate {
    param($Value)
    try {
        $text = Get-JarvisInsightSafeText -Value $Value
        if ([string]::IsNullOrWhiteSpace($text)) { return $null }
        return [datetime]::Parse($text)
    }
    catch {
        return $null
    }
}

function New-JarvisInsight {
    param(
        [string]$Type,
        [string]$Message,
        [string]$Severity = "media",
        [string]$SourceEntity = "",
        [string]$SourceId = "",
        [string]$Action = ""
    )

    return [pscustomobject]@{
        id = "insight-$Type-$SourceId"
        type = $Type
        message = $Message
        severity = $Severity
        source_entity = $SourceEntity
        source_id = $SourceId
        action = $Action
    }
}

function Get-JarvisInsights {
    $insights = @()
    $today = (Get-Date).Date
    $events = @()
    $subjects = @()
    $topics = @()
    $evaluations = @()
    $assignments = @()
    $schedules = @()

    if (Get-Command Get-CalendarVisibleEvents -ErrorAction SilentlyContinue) { $events = @(Get-CalendarVisibleEvents) }
    if (Get-Command Get-StudyVisibleSubjects -ErrorAction SilentlyContinue) { $subjects = @(Get-StudyVisibleSubjects) }
    if (Get-Command Get-StudyVisibleTopics -ErrorAction SilentlyContinue) { $topics = @(Get-StudyVisibleTopics) }
    if (Get-Command Get-StudyVisibleEvaluations -ErrorAction SilentlyContinue) { $evaluations = @(Get-StudyVisibleEvaluations) }
    if (Get-Command Get-StudyVisibleAssignments -ErrorAction SilentlyContinue) { $assignments = @(Get-StudyVisibleAssignments) }
    if (Get-Command Get-StudyVisibleSchedules -ErrorAction SilentlyContinue) { $schedules = @(Get-StudyVisibleSchedules) }

    $upcomingEvents = @($events | ForEach-Object {
        $date = ConvertTo-JarvisInsightDate -Value $_.starts_at
        if ($date -and $date.Date -ge $today -and $date.Date -le $today.AddDays(14)) {
            [pscustomobject]@{ event = $_; date = $date; days = [int]($date.Date - $today).TotalDays }
        }
    } | Sort-Object date)

    foreach ($item in @($upcomingEvents | Select-Object -First 4)) {
        $event = $item.event
        $daysText = if ($item.days -eq 0) { "hoy" } elseif ($item.days -eq 1) { "manana" } else { "en $($item.days) dias" }
        $severity = if ($item.days -le 2) { "alta" } elseif ($item.days -le 7) { "media" } else { "baja" }
        $insights += New-JarvisInsight -Type "calendar_upcoming" -Message "$(Get-JarvisInsightSafeText -Value $event.title -Fallback "Evento") $daysText." -Severity $severity -SourceEntity "calendar_events" -SourceId $event.id -Action "open_calendar"
    }

    $academicUpcoming = @($upcomingEvents | Where-Object { @("parcial", "final", "tp", "entrega", "exposicion") -contains (Get-JarvisInsightSafeText -Value $_.event.type) })
    if ($academicUpcoming.Count -ge 3) {
        $insights += New-JarvisInsight -Type "academic_density" -Message "Tenes $($academicUpcoming.Count) fechas academicas importantes durante los proximos 14 dias." -Severity "alta" -SourceEntity "calendar_events" -SourceId "academic-density" -Action "open_calendar"
    }

    for ($i = 0; $i -lt $academicUpcoming.Count; $i++) {
        for ($j = $i + 1; $j -lt $academicUpcoming.Count; $j++) {
            $distance = [math]::Abs(($academicUpcoming[$j].date.Date - $academicUpcoming[$i].date.Date).TotalDays)
            if ($distance -le 2) {
                $insights += New-JarvisInsight -Type "academic_collision" -Message "Tenes dos evaluaciones o entregas muy cercanas entre si." -Severity "alta" -SourceEntity "calendar_events" -SourceId "academic-collision" -Action "open_calendar"
                $i = $academicUpcoming.Count
                break
            }
        }
    }

    foreach ($evaluation in $evaluations) {
        if ((Get-JarvisInsightSafeText -Value $evaluation.status -Fallback "pendiente") -eq "completada") { continue }
        $event = $events | Where-Object { $_.id -eq $evaluation.calendar_event_id } | Select-Object -First 1
        $date = ConvertTo-JarvisInsightDate -Value $event.starts_at
        if (-not $date) { continue }
        $days = [int]($date.Date - $today).TotalDays
        if ($days -ge 0 -and $days -le 21) {
            $pendingTopics = @($topics | Where-Object {
                $_.subject_id -eq $evaluation.subject_id -and
                @("hecho", "completado", "aprobado") -notcontains (Get-JarvisInsightSafeText -Value $_.status)
            }).Count
            if ($pendingTopics -gt 0) {
                $insights += New-JarvisInsight -Type "evaluation_preparation" -Message "Faltan $days dias para $(Get-JarvisInsightSafeText -Value $evaluation.title -Fallback "una evaluacion") y quedan $pendingTopics temas pendientes." -Severity "media" -SourceEntity "study_evaluations" -SourceId $evaluation.id -Action "open_study"
            }
        }
    }

    $finalSubjects = @($subjects | Where-Object { (Get-JarvisInsightSafeText -Value $_.status) -eq "final_pendiente" })
    foreach ($subject in @($finalSubjects | Select-Object -First 2)) {
        $hasFutureEvent = @($events | Where-Object {
            $_.subject_id -eq $subject.id -and
            (ConvertTo-JarvisInsightDate -Value $_.starts_at) -and
            (ConvertTo-JarvisInsightDate -Value $_.starts_at).Date -ge $today
        }).Count -gt 0
        if (-not $hasFutureEvent) {
            $insights += New-JarvisInsight -Type "pending_final" -Message "$(Get-JarvisInsightSafeText -Value $subject.name -Fallback "Una materia") tiene final pendiente y todavia no tiene fecha cargada." -Severity "media" -SourceEntity "study_subjects" -SourceId $subject.id -Action "open_study"
        }
    }

    $tomorrow = $today.AddDays(1).DayOfWeek.ToString().ToLowerInvariant()
    $tomorrowSchedules = @($schedules | Where-Object { (Get-JarvisInsightSafeText -Value $_.day_of_week).ToLowerInvariant() -eq $tomorrow })
    foreach ($schedule in @($tomorrowSchedules | Select-Object -First 2)) {
        $subject = $subjects | Where-Object { $_.id -eq $schedule.subject_id } | Select-Object -First 1
        $insights += New-JarvisInsight -Type "class_tomorrow" -Message "Manana cursas $(Get-JarvisInsightSafeText -Value $subject.name -Fallback "una materia") a las $(Get-JarvisInsightSafeText -Value $schedule.starts_at)." -Severity "baja" -SourceEntity "study_schedules" -SourceId $schedule.id -Action "open_study"
    }

    return @($insights | Select-Object -First 8)
}
