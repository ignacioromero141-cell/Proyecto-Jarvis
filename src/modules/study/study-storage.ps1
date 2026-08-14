# Almacenamiento del modulo Estudio.
# Cada coleccion vive separada para sincronizar por entidad sin mezclar datos.

function Initialize-StudyStorage {
    param([string]$ProjectRoot)

    $script:StudyProjectRoot = $ProjectRoot
    $script:StudyDataDirectory = Join-Path $ProjectRoot "data\study"
    $script:StudyBackupDirectory = Join-Path $script:StudyDataDirectory "backups"
    $script:StudySubjectsFile = Join-Path $script:StudyDataDirectory "subjects.json"
    $script:StudyTopicsFile = Join-Path $script:StudyDataDirectory "topics.json"
    $script:StudyEvaluationsFile = Join-Path $script:StudyDataDirectory "evaluations.json"
    $script:StudyAssignmentsFile = Join-Path $script:StudyDataDirectory "assignments.json"
    $script:StudyNotesFile = Join-Path $script:StudyDataDirectory "notes.json"
    $script:StudySchedulesFile = Join-Path $script:StudyDataDirectory "schedules.json"

    if (-not (Test-Path -LiteralPath $script:StudyDataDirectory)) {
        New-Item -ItemType Directory -Path $script:StudyDataDirectory | Out-Null
    }
    if (-not (Test-Path -LiteralPath $script:StudyBackupDirectory)) {
        New-Item -ItemType Directory -Path $script:StudyBackupDirectory | Out-Null
    }

    foreach ($file in @(
        $script:StudySubjectsFile,
        $script:StudyTopicsFile,
        $script:StudyEvaluationsFile,
        $script:StudyAssignmentsFile,
        $script:StudyNotesFile,
        $script:StudySchedulesFile
    )) {
        if (-not (Test-Path -LiteralPath $file)) {
            "[]" | Set-Content -LiteralPath $file -Encoding UTF8
        }
    }
}

function Read-StudyJsonArray {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return @()
    }
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

function Write-StudyJsonArray {
    param(
        [string]$Path,
        [array]$Items,
        [string]$BackupReason = "study-auto"
    )

    if (Test-Path -LiteralPath $Path) {
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $safeReason = $BackupReason -replace "[^a-zA-Z0-9_-]", "-"
        $leaf = [System.IO.Path]::GetFileNameWithoutExtension($Path)
        $backupFile = Join-Path $script:StudyBackupDirectory "$leaf-$safeReason-$timestamp.json"
        Copy-Item -LiteralPath $Path -Destination $backupFile
    }

    ConvertTo-Json -InputObject $Items -Depth 12 |
        Set-Content -LiteralPath $Path -Encoding UTF8
}

function Read-StudySubjects { return Read-StudyJsonArray -Path $script:StudySubjectsFile }
function Read-StudyTopics { return Read-StudyJsonArray -Path $script:StudyTopicsFile }
function Read-StudyEvaluations { return Read-StudyJsonArray -Path $script:StudyEvaluationsFile }
function Read-StudyAssignments { return Read-StudyJsonArray -Path $script:StudyAssignmentsFile }
function Read-StudyNotes { return Read-StudyJsonArray -Path $script:StudyNotesFile }
function Read-StudySchedules { return Read-StudyJsonArray -Path $script:StudySchedulesFile }

function Write-StudySubjects {
    param([array]$Subjects, [string]$BackupReason = "subjects-update")
    Write-StudyJsonArray -Path $script:StudySubjectsFile -Items $Subjects -BackupReason $BackupReason
}

function Write-StudyTopics {
    param([array]$Topics, [string]$BackupReason = "topics-update")
    Write-StudyJsonArray -Path $script:StudyTopicsFile -Items $Topics -BackupReason $BackupReason
}

function Write-StudyEvaluations {
    param([array]$Evaluations, [string]$BackupReason = "evaluations-update")
    Write-StudyJsonArray -Path $script:StudyEvaluationsFile -Items $Evaluations -BackupReason $BackupReason
}

function Write-StudyAssignments {
    param([array]$Assignments, [string]$BackupReason = "assignments-update")
    Write-StudyJsonArray -Path $script:StudyAssignmentsFile -Items $Assignments -BackupReason $BackupReason
}

function Write-StudyNotes {
    param([array]$Notes, [string]$BackupReason = "notes-update")
    Write-StudyJsonArray -Path $script:StudyNotesFile -Items $Notes -BackupReason $BackupReason
}

function Write-StudySchedules {
    param([array]$Schedules, [string]$BackupReason = "schedules-update")
    Write-StudyJsonArray -Path $script:StudySchedulesFile -Items $Schedules -BackupReason $BackupReason
}
