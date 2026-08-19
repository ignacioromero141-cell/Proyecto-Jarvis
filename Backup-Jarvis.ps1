[CmdletBinding()]
param(
    [string]$ProjectRoot = $PSScriptRoot,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot "backups"),
    [Security.SecureString]$Password,
    [switch]$AllowUnencrypted,
    [int]$MaxSnapshotAttempts = 3
)

$ErrorActionPreference = "Stop"
$script:BackupFormatVersion = 1
$script:Iterations = 310000

function ConvertFrom-JarvisSecureString {
    param([Security.SecureString]$Value)
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
}

function Get-JarvisSha256Hex {
    param([byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return (($sha.ComputeHash($Bytes) | ForEach-Object { $_.ToString("x2") }) -join "") }
    finally { $sha.Dispose() }
}

function Get-JarvisFileHashHex {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-JarvisBackupFile {
    param([string]$RelativePath)
    $normalized = $RelativePath.Replace("\", "/")
    if ($normalized -match "(?i)(^|/)runtime(/|$)") { return $false }
    if ($normalized -match "(?i)(^|/)(temp|tmp|test-results?)(/|$)") { return $false }
    if ($normalized -match "(?i)\.(pid|lock|tmp|log)$") { return $false }
    return $true
}

function Get-JarvisRelativePath {
    param([string]$BasePath, [string]$ChildPath)
    $base = [IO.Path]::GetFullPath($BasePath).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $child = [IO.Path]::GetFullPath($ChildPath)
    if (-not $child.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) { throw "Ruta fuera del directorio esperado: $child" }
    return $child.Substring($base.Length)
}

function Get-JarvisSourceFiles {
    param([string]$DataRoot)
    if (-not (Test-Path -LiteralPath $DataRoot -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $DataRoot -File -Recurse | ForEach-Object {
        $relative = Get-JarvisRelativePath -BasePath $DataRoot -ChildPath $_.FullName
        if (Test-JarvisBackupFile -RelativePath $relative) {
            [pscustomobject]@{ Source = $_.FullName; Relative = $relative.Replace("\", "/"); Length = $_.Length }
        }
    } | Sort-Object Relative)
}

function Read-JarvisJsonFile {
    param([string]$Path, $Default = @())
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $Default }
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Remove-JarvisTransientIdentitySecrets {
    param([string]$SnapshotDataRoot)
    $identityPath = Join-Path $SnapshotDataRoot "identity.json"
    if (-not (Test-Path -LiteralPath $identityPath -PathType Leaf)) { return }
    $identity = Get-Content -LiteralPath $identityPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($name in @("pairing_code", "pairing_token", "pairing_expires_at")) {
        if ($identity.PSObject.Properties.Name -contains $name) { $identity.PSObject.Properties.Remove($name) }
    }
    [IO.File]::WriteAllText($identityPath, ($identity | ConvertTo-Json -Depth 30), [Text.UTF8Encoding]::new($false))
}

function ConvertTo-JarvisSortedObject {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [string] -or $Value -is [ValueType]) { return $Value }
    if ($Value -is [Collections.IDictionary]) {
        $ordered = [ordered]@{}
        foreach ($key in @($Value.Keys | Sort-Object)) { $ordered[$key] = ConvertTo-JarvisSortedObject $Value[$key] }
        return $ordered
    }
    if ($Value -is [Collections.IEnumerable]) {
        return ,@($Value | ForEach-Object { ConvertTo-JarvisSortedObject $_ })
    }
    $object = [ordered]@{}
    foreach ($property in @($Value.PSObject.Properties | Sort-Object Name)) {
        $object[$property.Name] = ConvertTo-JarvisSortedObject $property.Value
    }
    return $object
}

function ConvertTo-JarvisCanonicalJson {
    param($Value)
    $sorted = ConvertTo-JarvisSortedObject $Value
    if ($null -eq $sorted -and $Value -is [Collections.IEnumerable] -and $Value -isnot [string]) { $sorted = @() }
    return (ConvertTo-Json -InputObject $sorted -Depth 100 -Compress)
}

function Get-JarvisJsonHash {
    param($Value)
    return Get-JarvisSha256Hex -Bytes ([Text.Encoding]::UTF8.GetBytes((ConvertTo-JarvisCanonicalJson $Value)))
}

function New-JarvisNotebookPackage {
    param([string]$SnapshotDataRoot, [string]$ExportedAt)
    $identity = Read-JarvisJsonFile (Join-Path $SnapshotDataRoot "identity.json") ([pscustomobject]@{})
    $mapping = [ordered]@{
        records = "records.json"
        finance_movements = "finance/movements.json"
        finance_categories = "finance/categories.json"
        finance_priorities = "finance/priorities.json"
        finance_payment_methods = "finance/payment-methods.json"
        finance_settings = "finance/settings.json"
        calendar_events = "calendar/events.json"
        study_subjects = "study/subjects.json"
        study_topics = "study/topics.json"
        study_evaluations = "study/evaluations.json"
        study_assignments = "study/assignments.json"
        study_notes = "study/notes.json"
        study_schedules = "study/schedules.json"
        file_assets = "files/assets.json"
        file_links = "files/links.json"
        local_file_roots = "files/local-roots.json"
        local_file_locations = "files/local-locations.json"
        sync_changes = "sync/changes.json"
        sync_conflicts = "sync/conflicts.json"
        metadata = $null
    }
    $stores = [ordered]@{}
    foreach ($entry in $mapping.GetEnumerator()) {
        if ($null -eq $entry.Value) { $stores[$entry.Key] = @(); continue }
        $value = Read-JarvisJsonFile (Join-Path $SnapshotDataRoot $entry.Value) @()
        if ($entry.Key -eq "finance_settings" -and $value -isnot [Collections.IEnumerable]) { $value = @($value) }
        $stores[$entry.Key] = @($value)
    }
    $counts = [ordered]@{}
    $total = 0
    foreach ($name in $stores.Keys) { $counts[$name] = @($stores[$name]).Count; $total += $counts[$name] }
    $changes = @($stores.sync_changes)
    $pending = @($changes | Where-Object { -not $_.synced_at -and -not $_.applied_at })
    $linkedJson = ConvertTo-Json @($identity.linked_devices) -Depth 20 -Compress
    $localStorage = [ordered]@{
        jarvis_workspace_id = "$($identity.workspace_id)"
        jarvis_workspace_name = "$($identity.workspace_name)"
        jarvis_device_id = "$($identity.device_id)"
        jarvis_device_name = "$($identity.device_name)"
        jarvis_sync_secret = "$($identity.sync_secret)"
        jarvis_linked_devices = $linkedJson
    }
    $packageIdentity = [ordered]@{
        workspace_id = "$($identity.workspace_id)"; workspace_name = "$($identity.workspace_name)"
        device_id = "$($identity.device_id)"; device_name = "$($identity.device_name)"
        sync_secret = "$($identity.sync_secret)"; linked_devices = @($identity.linked_devices)
    }
    $package = [ordered]@{
        format_version = 1; app_version = "0.6-phase0"; exported_at = $ExportedAt
        source_origin = "notebook-json"; source_protocol = "file:"; source_kind = "notebook-json-snapshot"
        database_name = "jarvis-notebook-json"; database_version = 1
        workspace_id = "$($identity.workspace_id)"; device_id = "$($identity.device_id)"
        identity = $packageIdentity; local_storage = $localStorage; stores = $stores
        pending_changes = $pending; conflicts = @($stores.sync_conflicts); cursors = [ordered]@{}
        statistics = [ordered]@{ store_counts=$counts; total_records=$total; total_entities=($total - @($stores.sync_changes).Count - @($stores.sync_conflicts).Count); logically_deleted=@($stores.Values | ForEach-Object { @($_) } | Where-Object { $_.deleted_at }).Count; pending_changes=$pending.Count; confirmed_changes=@($changes | Where-Object { $_.synced_at -or $_.applied_at }).Count; received_changes=0; imported_snapshots=0; conflicts=@($stores.sync_conflicts).Count }
        serialization = [ordered]@{ format="jarvis-structured-json-v1"; warnings=@("Los archivos binarios no se incluyen; file_assets contiene su metadata.") }
        checksums = [ordered]@{}
    }
    $storeHashes = [ordered]@{}
    foreach ($name in $stores.Keys) { $storeHashes[$name] = Get-JarvisJsonHash $stores[$name] }
    $withoutChecksums = [ordered]@{}
    foreach ($key in $package.Keys) { if ($key -ne "checksums") { $withoutChecksums[$key] = $package[$key] } }
    $package.checksums = [ordered]@{ algorithm="SHA-256"; stores=$storeHashes; local_storage=(Get-JarvisJsonHash $localStorage); payload=(Get-JarvisJsonHash $withoutChecksums) }
    return $package
}

function Protect-JarvisBytes {
    param([byte[]]$PlainBytes, [string]$PlainPassword)
    $salt = New-Object byte[] 16; $iv = New-Object byte[] 16
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($salt); $rng.GetBytes($iv) } finally { $rng.Dispose() }
    $derive = [Security.Cryptography.Rfc2898DeriveBytes]::new($PlainPassword, $salt, $script:Iterations, [Security.Cryptography.HashAlgorithmName]::SHA256)
    try { $keyMaterial = $derive.GetBytes(64) } finally { $derive.Dispose() }
    $encKey = $keyMaterial[0..31]; $macKey = $keyMaterial[32..63]
    $aes = [Security.Cryptography.Aes]::Create()
    try {
        $aes.KeySize=256; $aes.Mode=[Security.Cryptography.CipherMode]::CBC; $aes.Padding=[Security.Cryptography.PaddingMode]::PKCS7; $aes.Key=$encKey; $aes.IV=$iv
        $encryptor = $aes.CreateEncryptor()
        try { $ciphertext = $encryptor.TransformFinalBlock($PlainBytes, 0, $PlainBytes.Length) } finally { $encryptor.Dispose() }
    } finally { $aes.Dispose() }
    $authenticated = New-Object byte[] ($salt.Length + $iv.Length + $ciphertext.Length)
    [Array]::Copy($salt,0,$authenticated,0,$salt.Length); [Array]::Copy($iv,0,$authenticated,$salt.Length,$iv.Length); [Array]::Copy($ciphertext,0,$authenticated,$salt.Length+$iv.Length,$ciphertext.Length)
    $hmac = [Security.Cryptography.HMACSHA256]::new($macKey)
    try { $tag = $hmac.ComputeHash($authenticated) } finally { $hmac.Dispose(); [Array]::Clear($keyMaterial,0,$keyMaterial.Length) }
    return [ordered]@{
        encrypted=$true; crypto_format_version=1; content_format="jarvis-notebook-zip-v1"
        kdf=[ordered]@{ name="PBKDF2"; hash="SHA-256"; iterations=$script:Iterations; salt=[Convert]::ToBase64String($salt) }
        cipher=[ordered]@{ name="AES-256-CBC"; padding="PKCS7"; iv=[Convert]::ToBase64String($iv) }
        authentication=[ordered]@{ name="HMAC-SHA-256"; construction="encrypt-then-MAC"; tag=[Convert]::ToBase64String($tag) }
        ciphertext=[Convert]::ToBase64String($ciphertext)
    }
}

$resolvedRoot = [IO.Path]::GetFullPath($ProjectRoot)
$dataRoot = Join-Path $resolvedRoot "data"
if (-not (Test-Path -LiteralPath $dataRoot -PathType Container)) { throw "No existe el directorio data de Jarvis: $dataRoot" }
if ($MaxSnapshotAttempts -lt 1 -or $MaxSnapshotAttempts -gt 10) { throw "MaxSnapshotAttempts debe estar entre 1 y 10." }
if (-not $AllowUnencrypted -and $null -eq $Password) { $Password = Read-Host "Contraseña para cifrar el backup (minimo 10 caracteres)" -AsSecureString }
$plainPassword = if ($null -ne $Password) { ConvertFrom-JarvisSecureString $Password } else { "" }
if (-not $AllowUnencrypted -and $plainPassword.Length -lt 10) { throw "La contraseña debe tener al menos 10 caracteres." }

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("jarvis-backup-" + [guid]::NewGuid().ToString("N"))
$stageRoot = Join-Path $tempRoot "snapshot"
$stageData = Join-Path $stageRoot "data"
[IO.Directory]::CreateDirectory($stageData) | Out-Null
try {
    $snapshotComplete = $false
    for ($attempt=1; $attempt -le $MaxSnapshotAttempts -and -not $snapshotComplete; $attempt++) {
        if (Test-Path -LiteralPath $stageData) { Get-ChildItem -LiteralPath $stageData -Force | Remove-Item -Recurse -Force }
        $files = Get-JarvisSourceFiles -DataRoot $dataRoot
        $before = @{}; foreach ($file in $files) { $before[$file.Relative] = Get-JarvisFileHashHex $file.Source }
        foreach ($file in $files) {
            $destination = Join-Path $stageData $file.Relative
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
            Copy-Item -LiteralPath $file.Source -Destination $destination
        }
        $afterFiles = Get-JarvisSourceFiles -DataRoot $dataRoot
        $after = @{}; foreach ($file in $afterFiles) { $after[$file.Relative] = Get-JarvisFileHashHex $file.Source }
        $snapshotComplete = ($before.Count -eq $after.Count -and @($before.Keys | Where-Object { -not $after.ContainsKey($_) -or $before[$_] -ne $after[$_] }).Count -eq 0)
    }
    if (-not $snapshotComplete) { throw "Los datos cambiaron durante todos los intentos. Detene Jarvis y volve a ejecutar el backup." }

    # Los codigos/tokens de vinculacion son efimeros y no son necesarios para
    # restaurar identidad, dispositivos o la credencial LAN estable.
    Remove-JarvisTransientIdentitySecrets -SnapshotDataRoot $stageData

    $exportedAt = (Get-Date).ToUniversalTime().ToString("o")
    $package = New-JarvisNotebookPackage -SnapshotDataRoot $stageData -ExportedAt $exportedAt
    $comparisonDirectory = Join-Path $stageRoot "comparison"; [IO.Directory]::CreateDirectory($comparisonDirectory) | Out-Null
    $packagePath = Join-Path $comparisonDirectory "jarvis-notebook-export-v1.json"
    [IO.File]::WriteAllText($packagePath, ($package | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))

    $manifestFiles = @(Get-ChildItem -LiteralPath $stageData -File -Recurse | ForEach-Object { [ordered]@{ path=("data/" + (Get-JarvisRelativePath -BasePath $stageData -ChildPath $_.FullName).Replace("\","/")); size=$_.Length; sha256=(Get-JarvisFileHashHex $_.FullName) } })
    $manifest = [ordered]@{ format="jarvis-notebook-backup"; format_version=1; created_at=$exportedAt; project_name=(Split-Path $resolvedRoot -Leaf); file_count=$manifestFiles.Count; files=$manifestFiles; excluded=@("data/runtime/**","*.pid","*.lock","*.tmp","*.log","pairing_code","pairing_token","pairing_expires_at","test artifacts"); comparison_package="comparison/jarvis-notebook-export-v1.json"; comparison_sha256=(Get-JarvisFileHashHex $packagePath) }
    [IO.File]::WriteAllText((Join-Path $stageRoot "manifest.json"), ($manifest | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))

    [IO.Directory]::CreateDirectory([IO.Path]::GetFullPath($OutputDirectory)) | Out-Null
    $stamp = (Get-Date).ToString("yyyy-MM-ddTHHmmss")
    $baseName = "jarvis-notebook-backup-$stamp"
    $zipPath = Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) "$baseName.zip"
    $suffix=1
    while ((Test-Path -LiteralPath $zipPath) -or (Test-Path -LiteralPath ([IO.Path]::ChangeExtension($zipPath, ".encrypted.json")))) {
        $zipPath=Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) "$baseName-$suffix.zip"; $suffix++
    }
    Compress-Archive -Path (Join-Path $stageRoot "*") -DestinationPath $zipPath -CompressionLevel Optimal
    if ($AllowUnencrypted) {
        Write-Warning "Backup SIN CIFRAR. Contiene identidad y credencial LAN. Guardalo en un medio seguro."
        [pscustomobject]@{ Path=$zipPath; Encrypted=$false; Files=$manifestFiles.Count; Manifest=$manifest } | Write-Output
    } else {
        $wrapper = Protect-JarvisBytes -PlainBytes ([IO.File]::ReadAllBytes($zipPath)) -PlainPassword $plainPassword
        $encryptedPath = [IO.Path]::ChangeExtension($zipPath, ".encrypted.json")
        [IO.File]::WriteAllText($encryptedPath, ($wrapper | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
        Remove-Item -LiteralPath $zipPath -Force
        [pscustomobject]@{ Path=$encryptedPath; Encrypted=$true; Files=$manifestFiles.Count; Manifest=$manifest } | Write-Output
    }
} finally {
    if ($plainPassword) { $plainPassword = $null }
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}
