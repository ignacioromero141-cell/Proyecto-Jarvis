# Almacenamiento de archivos locales.
# file_assets y file_links son metadata sincronizable; roots/locations son locales por dispositivo.

function Initialize-FilesStorage {
    param([string]$ProjectRoot)

    $script:FilesProjectRoot = $ProjectRoot
    $script:FilesDataDirectory = Join-Path $ProjectRoot "data\files"
    $script:FilesBackupDirectory = Join-Path $script:FilesDataDirectory "backups"
    $script:FileAssetsFile = Join-Path $script:FilesDataDirectory "assets.json"
    $script:FileLinksFile = Join-Path $script:FilesDataDirectory "links.json"
    $script:FileRootsFile = Join-Path $script:FilesDataDirectory "local-roots.json"
    $script:FileLocationsFile = Join-Path $script:FilesDataDirectory "local-locations.json"

    if (-not (Test-Path -LiteralPath $script:FilesDataDirectory)) {
        New-Item -ItemType Directory -Path $script:FilesDataDirectory | Out-Null
    }
    if (-not (Test-Path -LiteralPath $script:FilesBackupDirectory)) {
        New-Item -ItemType Directory -Path $script:FilesBackupDirectory | Out-Null
    }
    foreach ($file in @($script:FileAssetsFile, $script:FileLinksFile, $script:FileRootsFile, $script:FileLocationsFile)) {
        if (-not (Test-Path -LiteralPath $file)) {
            "[]" | Set-Content -LiteralPath $file -Encoding UTF8
        }
    }
}

function Read-FilesJsonArray {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return @() }
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $content = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($content)) { return @() }
    $items = ConvertFrom-Json -InputObject $content
    return @($items | ForEach-Object { $_ })
}

function Write-FilesJsonArray {
    param([string]$Path, [array]$Items, [string]$BackupReason = "files-auto")

    if (Test-Path -LiteralPath $Path) {
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $safeReason = $BackupReason -replace "[^a-zA-Z0-9_-]", "-"
        $leaf = [System.IO.Path]::GetFileNameWithoutExtension($Path)
        $backupFile = Join-Path $script:FilesBackupDirectory "$leaf-$safeReason-$timestamp.json"
        Copy-Item -LiteralPath $Path -Destination $backupFile
    }

    ConvertTo-Json -InputObject $Items -Depth 12 |
        Set-Content -LiteralPath $Path -Encoding UTF8
}

function Read-FileAssets { return Read-FilesJsonArray -Path $script:FileAssetsFile }
function Read-FileLinks { return Read-FilesJsonArray -Path $script:FileLinksFile }
function Read-FileRoots { return Read-FilesJsonArray -Path $script:FileRootsFile }
function Read-FileLocations { return Read-FilesJsonArray -Path $script:FileLocationsFile }

function Write-FileAssets {
    param([array]$Assets, [string]$BackupReason = "assets-update")
    Write-FilesJsonArray -Path $script:FileAssetsFile -Items $Assets -BackupReason $BackupReason
}

function Write-FileLinks {
    param([array]$Links, [string]$BackupReason = "links-update")
    Write-FilesJsonArray -Path $script:FileLinksFile -Items $Links -BackupReason $BackupReason
}

function Write-FileRoots {
    param([array]$Roots, [string]$BackupReason = "roots-update")
    Write-FilesJsonArray -Path $script:FileRootsFile -Items $Roots -BackupReason $BackupReason
}

function Write-FileLocations {
    param([array]$Locations, [string]$BackupReason = "locations-update")
    Write-FilesJsonArray -Path $script:FileLocationsFile -Items $Locations -BackupReason $BackupReason
}
