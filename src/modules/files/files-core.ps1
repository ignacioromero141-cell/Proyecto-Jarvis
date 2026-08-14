# Reglas para archivos locales V1.
# No mueve, no renombra y no borra archivos; solo registra metadata y permite abrirlos.

. (Join-Path $PSScriptRoot "files-storage.ps1")

function Get-FilesSafeText {
    param($Value, [string]$Fallback = "")
    if ($null -eq $Value) { return $Fallback }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $Fallback }
    return $text.Trim()
}

function Get-FilesLocalDeviceId {
    if (Get-Command Get-JarvisDeviceId -ErrorAction SilentlyContinue) {
        return Get-JarvisDeviceId
    }
    return "notebook-local"
}

function Set-FilesProperty {
    param($Item, [string]$Name, $Value)
    if ($Item.PSObject.Properties.Name -contains $Name) { $Item.$Name = $Value }
    else { $Item | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

function Add-FilesSyncChange {
    param([string]$Entity, [string]$EntityId, [string]$Operation, $Value)
    if (Get-Command Add-JarvisSyncChange -ErrorAction SilentlyContinue) {
        Add-JarvisSyncChange -Entity $Entity -EntityId $EntityId -Operation $Operation -Value $Value | Out-Null
    }
}

function Update-FilesSyncMetadata {
    param($Item)
    $revision = 0
    try { $revision = [int](Get-FilesSafeText -Value $Item.revision -Fallback "0") } catch { $revision = 0 }
    Set-FilesProperty -Item $Item -Name "device_id" -Value (Get-FilesSafeText -Value $Item.device_id -Fallback (Get-FilesLocalDeviceId))
    Set-FilesProperty -Item $Item -Name "revision" -Value ($revision + 1)
    Set-FilesProperty -Item $Item -Name "synced_at" -Value $null
}

function Get-FileVisibleAssets {
    return @(Read-FileAssets | Where-Object { [string]::IsNullOrWhiteSpace((Get-FilesSafeText -Value $_.deleted_at)) })
}

function Get-FileVisibleLinks {
    return @(Read-FileLinks | Where-Object { [string]::IsNullOrWhiteSpace((Get-FilesSafeText -Value $_.deleted_at)) })
}

function Get-FileKind {
    param([string]$Extension)
    $ext = (Get-FilesSafeText -Value $Extension).ToLowerInvariant()
    if (@(".jpg", ".jpeg", ".png", ".gif", ".webp", ".heic", ".bmp") -contains $ext) { return "photo" }
    if ($ext -eq ".pdf") { return "pdf" }
    if (@(".doc", ".docx", ".txt", ".md", ".ppt", ".pptx", ".xls", ".xlsx") -contains $ext) { return "document" }
    return "other"
}

function Add-FileRoot {
    param([string]$Path, [string]$Label = "")

    $safePath = Get-FilesSafeText -Value $Path
    if ([string]::IsNullOrWhiteSpace($safePath)) { throw "Elegi una carpeta." }
    $resolved = Resolve-Path -LiteralPath $safePath -ErrorAction Stop
    if (-not (Test-Path -LiteralPath $resolved.Path -PathType Container)) {
        throw "La ruta autorizada debe ser una carpeta."
    }

    $roots = @(Read-FileRoots)
    $existing = $roots | Where-Object { $_.path -eq $resolved.Path } | Select-Object -First 1
    $now = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    if ($existing) {
        $existing.label = (Get-FilesSafeText -Value $Label -Fallback $existing.label)
        $existing.updated_at = $now
        Write-FileRoots -Roots $roots -BackupReason "root-update"
        return $existing
    }

    $root = [pscustomobject]@{
        id = "root-$([guid]::NewGuid().ToString("N"))"
        label = (Get-FilesSafeText -Value $Label -Fallback (Split-Path -Leaf $resolved.Path))
        path = $resolved.Path
        permission = "read_open"
        device_id = Get-FilesLocalDeviceId
        created_at = $now
        updated_at = $now
    }
    $roots += $root
    Write-FileRoots -Roots $roots -BackupReason "root-add"
    return $root
}

function Get-FileFingerprint {
    param($File)
    return "$($File.Name)|$($File.Length)|$($File.LastWriteTimeUtc.ToString("yyyy-MM-ddTHH:mm:ss"))"
}

function Get-FileRelativePath {
    param(
        [string]$RootPath,
        [string]$FilePath
    )

    $rootFull = [System.IO.Path]::GetFullPath($RootPath).TrimEnd("\", "/")
    $fileFull = [System.IO.Path]::GetFullPath($FilePath)
    if ($fileFull.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $fileFull.Substring($rootFull.Length).TrimStart("\", "/")
    }
    return [System.IO.Path]::GetFileName($fileFull)
}

function Ensure-FileLink {
    param([string]$FileId, [string]$TargetType, [string]$TargetId, [string]$Category = "archivo")

    if ([string]::IsNullOrWhiteSpace($TargetType) -or [string]::IsNullOrWhiteSpace($TargetId)) {
        return $null
    }
    $links = @(Read-FileLinks)
    $existing = $links | Where-Object {
        $_.file_id -eq $FileId -and $_.target_type -eq $TargetType -and $_.target_id -eq $TargetId -and
        [string]::IsNullOrWhiteSpace((Get-FilesSafeText -Value $_.deleted_at))
    } | Select-Object -First 1
    if ($existing) { return $existing }

    $now = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    $link = [pscustomobject]@{
        id = "file-link-$([guid]::NewGuid().ToString("N"))"
        file_id = $FileId
        target_type = $TargetType
        target_id = $TargetId
        category = (Get-FilesSafeText -Value $Category -Fallback "archivo")
        device_id = Get-FilesLocalDeviceId
        revision = 1
        deleted_at = $null
        synced_at = $null
        created_at = $now
        updated_at = $now
    }
    $links += $link
    Write-FileLinks -Links $links -BackupReason "link-add"
    Add-FilesSyncChange -Entity "file_links" -EntityId $link.id -Operation "create" -Value $link
    return $link
}

function Scan-FileRoot {
    param(
        [string]$RootId,
        [string]$TargetType = "",
        [string]$TargetId = "",
        [int]$Limit = 500
    )

    $root = Read-FileRoots | Where-Object { $_.id -eq $RootId } | Select-Object -First 1
    if (-not $root) { throw "Primero autoriza una carpeta." }
    if (-not (Test-Path -LiteralPath $root.path -PathType Container)) { throw "La carpeta autorizada ya no esta disponible." }

    $assets = @(Read-FileAssets)
    $locations = @(Read-FileLocations)
    $now = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    $scanned = 0
    $added = 0
    $linked = 0

    foreach ($file in @(Get-ChildItem -LiteralPath $root.path -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First $Limit)) {
        $scanned += 1
        $relativePath = Get-FileRelativePath -RootPath $root.path -FilePath $file.FullName
        $location = $locations | Where-Object { $_.root_id -eq $RootId -and $_.relative_path -eq $relativePath } | Select-Object -First 1
        $fingerprint = Get-FileFingerprint -File $file
        $asset = $null
        if ($location) {
            $asset = $assets | Where-Object { $_.id -eq $location.file_id } | Select-Object -First 1
        }
        if (-not $asset) {
            $asset = $assets | Where-Object { $_.fingerprint -eq $fingerprint } | Select-Object -First 1
        }
        if (-not $asset) {
            $asset = [pscustomobject]@{
                id = "file-$([guid]::NewGuid().ToString("N"))"
                display_name = $file.Name
                kind = Get-FileKind -Extension $file.Extension
                extension = $file.Extension
                size = [int64]$file.Length
                fingerprint = $fingerprint
                last_modified_at = $file.LastWriteTime.ToString("yyyy-MM-ddTHH:mm:ss")
                device_id = Get-FilesLocalDeviceId
                revision = 1
                deleted_at = $null
                synced_at = $null
                created_at = $now
                updated_at = $now
            }
            $assets += $asset
            $added += 1
            Add-FilesSyncChange -Entity "file_assets" -EntityId $asset.id -Operation "create" -Value $asset
        }

        if (-not $location) {
            $locations += [pscustomobject]@{
                id = "location-$([guid]::NewGuid().ToString("N"))"
                file_id = $asset.id
                root_id = $RootId
                relative_path = $relativePath
                absolute_path = $file.FullName
                device_id = Get-FilesLocalDeviceId
                available = $true
                last_seen_at = $now
            }
        }
        else {
            $location.available = $true
            $location.last_seen_at = $now
            $location.absolute_path = $file.FullName
            $location.file_id = $asset.id
        }

        $createdLink = Ensure-FileLink -FileId $asset.id -TargetType $TargetType -TargetId $TargetId -Category $(if ((Get-FileKind -Extension $file.Extension) -eq "photo") { "foto" } else { "archivo" })
        if ($createdLink) { $linked += 1 }
    }

    Write-FileAssets -Assets $assets -BackupReason "scan-assets"
    Write-FileLocations -Locations $locations -BackupReason "scan-locations"
    return [pscustomobject]@{ scanned = $scanned; added = $added; linked = $linked; limit = $Limit }
}

function Open-FileAsset {
    param([string]$FileId)

    $location = Read-FileLocations |
        Where-Object { $_.file_id -eq $FileId -and $_.available -ne $false } |
        Select-Object -First 1
    if (-not $location) { throw "Este archivo no tiene una ubicacion local disponible en esta notebook." }
    if (-not (Test-Path -LiteralPath $location.absolute_path -PathType Leaf)) { throw "El archivo ya no esta en esa ruta local." }
    Start-Process -FilePath $location.absolute_path
    return [pscustomobject]@{ opened = $true; file_id = $FileId }
}

function Get-FilesSummary {
    return [pscustomobject]@{
        assets = @(Get-FileVisibleAssets)
        links = @(Get-FileVisibleLinks)
        roots = @(Read-FileRoots)
        locations = @(Read-FileLocations | ForEach-Object {
            [pscustomobject]@{
                id = $_.id
                file_id = $_.file_id
                root_id = $_.root_id
                relative_path = $_.relative_path
                device_id = $_.device_id
                available = $_.available
                last_seen_at = $_.last_seen_at
            }
        })
    }
}
