[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BackupPath,
    [Parameter(Mandatory)][string]$DestinationDirectory,
    [Security.SecureString]$Password
)

$ErrorActionPreference = "Stop"
$script:MaxArchiveEntries = 100000
$script:MaxUncompressedBytes = 2GB

function ConvertFrom-JarvisSecureString {
    param([Security.SecureString]$Value)
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
}

function Get-JarvisFileHashHex {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-JarvisFixedTimeEquals {
    param([byte[]]$Left, [byte[]]$Right)
    if ($Left.Length -ne $Right.Length) { return $false }
    $difference = 0
    for ($index = 0; $index -lt $Left.Length; $index++) {
        $difference = $difference -bor ($Left[$index] -bxor $Right[$index])
    }
    return $difference -eq 0
}

function Get-JarvisSafeRestorePath {
    param([string]$Root, [string]$RelativePath)
    if ([string]::IsNullOrWhiteSpace($RelativePath) -or $RelativePath.IndexOf([char]0) -ge 0) {
        throw "El backup contiene una ruta vacia o invalida."
    }
    $normalized = $RelativePath.Replace('/', [IO.Path]::DirectorySeparatorChar).Replace('\', [IO.Path]::DirectorySeparatorChar)
    if ([IO.Path]::IsPathRooted($normalized)) { throw "El backup contiene una ruta absoluta no permitida: $RelativePath" }
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $candidate = [IO.Path]::GetFullPath((Join-Path $rootPath $normalized))
    if (-not $candidate.StartsWith($rootPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw "El backup intento escribir fuera del directorio de destino: $RelativePath"
    }
    return $candidate
}

function Test-JarvisZipEntries {
    param([string]$ZipPath, [string]$DestinationRoot)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        if ($archive.Entries.Count -gt $script:MaxArchiveEntries) { throw "El backup contiene demasiados archivos." }
        [long]$totalBytes = 0
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($entry in $archive.Entries) {
            $totalBytes += [long]$entry.Length
            if ($totalBytes -gt $script:MaxUncompressedBytes) { throw "El backup supera el limite de tamaño permitido." }
            $target = Get-JarvisSafeRestorePath -Root $DestinationRoot -RelativePath $entry.FullName
            if (-not $seen.Add($target)) { throw "El backup contiene una ruta duplicada: $($entry.FullName)" }
        }
    }
    finally { $archive.Dispose() }
}

$source = [IO.Path]::GetFullPath($BackupPath)
$destination = [IO.Path]::GetFullPath($DestinationDirectory)
if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "No existe el backup." }
if ((Test-Path -LiteralPath $destination) -and @(Get-ChildItem -LiteralPath $destination -Force).Count) {
    throw "El directorio de destino debe estar vacio."
}
[IO.Directory]::CreateDirectory($destination) | Out-Null

$tempZip = $null
$plainPassword = ""
try {
    if ($source.EndsWith(".json", [StringComparison]::OrdinalIgnoreCase)) {
        $wrapper = Get-Content -LiteralPath $source -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($wrapper.content_format -ne "jarvis-notebook-zip-v1") { throw "Formato cifrado desconocido." }
        if ($wrapper.crypto_format_version -ne 1 -or $wrapper.kdf.name -ne "PBKDF2" -or $wrapper.kdf.hash -ne "SHA-256" -or $wrapper.cipher.name -ne "AES-256-CBC" -or $wrapper.authentication.name -ne "HMAC-SHA-256") {
            throw "Parametros criptograficos no compatibles."
        }
        $iterations = [int]$wrapper.kdf.iterations
        if ($iterations -lt 100000 -or $iterations -gt 2000000) { throw "Cantidad de iteraciones invalida." }
        if ($null -eq $Password) { $Password = Read-Host "Contraseña del backup" -AsSecureString }
        $plainPassword = ConvertFrom-JarvisSecureString $Password
        $salt = [Convert]::FromBase64String($wrapper.kdf.salt)
        $iv = [Convert]::FromBase64String($wrapper.cipher.iv)
        $ciphertext = [Convert]::FromBase64String($wrapper.ciphertext)
        $expectedTag = [Convert]::FromBase64String($wrapper.authentication.tag)
        if ($salt.Length -ne 16 -or $iv.Length -ne 16 -or $expectedTag.Length -ne 32 -or $ciphertext.Length -eq 0 -or ($ciphertext.Length % 16) -ne 0) {
            throw "Estructura criptografica invalida."
        }

        $derive = [Security.Cryptography.Rfc2898DeriveBytes]::new($plainPassword, $salt, $iterations, [Security.Cryptography.HashAlgorithmName]::SHA256)
        try { $keyMaterial = $derive.GetBytes(64) } finally { $derive.Dispose() }
        $encryptionKey = $keyMaterial[0..31]
        $authenticationKey = $keyMaterial[32..63]
        $authenticated = New-Object byte[] ($salt.Length + $iv.Length + $ciphertext.Length)
        [Array]::Copy($salt, 0, $authenticated, 0, $salt.Length)
        [Array]::Copy($iv, 0, $authenticated, $salt.Length, $iv.Length)
        [Array]::Copy($ciphertext, 0, $authenticated, $salt.Length + $iv.Length, $ciphertext.Length)
        $hmac = [Security.Cryptography.HMACSHA256]::new($authenticationKey)
        try { $actualTag = $hmac.ComputeHash($authenticated) } finally { $hmac.Dispose() }
        if (-not (Test-JarvisFixedTimeEquals $actualTag $expectedTag)) {
            throw "Contraseña incorrecta o archivo dañado. No se restauro nada."
        }

        $aes = [Security.Cryptography.Aes]::Create()
        try {
            $aes.KeySize = 256
            $aes.Mode = [Security.Cryptography.CipherMode]::CBC
            $aes.Padding = [Security.Cryptography.PaddingMode]::PKCS7
            $aes.Key = $encryptionKey
            $aes.IV = $iv
            $decryptor = $aes.CreateDecryptor()
            try { $bytes = $decryptor.TransformFinalBlock($ciphertext, 0, $ciphertext.Length) }
            finally { $decryptor.Dispose() }
        }
        finally {
            $aes.Dispose()
            [Array]::Clear($keyMaterial, 0, $keyMaterial.Length)
        }
        $tempZip = Join-Path ([IO.Path]::GetTempPath()) ("jarvis-restore-" + [guid]::NewGuid().ToString("N") + ".zip")
        [IO.File]::WriteAllBytes($tempZip, $bytes)
        $zip = $tempZip
    }
    else { $zip = $source }

    Test-JarvisZipEntries -ZipPath $zip -DestinationRoot $destination
    Expand-Archive -LiteralPath $zip -DestinationPath $destination

    $manifestPath = Join-Path $destination "manifest.json"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Falta manifest.json." }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.format -ne "jarvis-notebook-backup" -or [int]$manifest.format_version -ne 1) { throw "Manifest de backup no compatible." }

    $allowedFiles = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    [void]$allowedFiles.Add([IO.Path]::GetFullPath($manifestPath))
    $comparisonPath = Get-JarvisSafeRestorePath -Root $destination -RelativePath ([string]$manifest.comparison_package)
    [void]$allowedFiles.Add($comparisonPath)
    foreach ($file in @($manifest.files)) {
        $path = Get-JarvisSafeRestorePath -Root $destination -RelativePath ([string]$file.path)
        [void]$allowedFiles.Add($path)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-JarvisFileHashHex $path) -ne ([string]$file.sha256).ToLowerInvariant()) {
            throw "Fallo de integridad: $($file.path)"
        }
    }
    if (-not (Test-Path -LiteralPath $comparisonPath -PathType Leaf)) { throw "Falta el paquete de comparacion." }
    if ([string]::IsNullOrWhiteSpace([string]$manifest.comparison_sha256) -or (Get-JarvisFileHashHex $comparisonPath) -ne ([string]$manifest.comparison_sha256).ToLowerInvariant()) {
        throw "Fallo de integridad en el paquete de comparacion."
    }
    $actualFiles = @(Get-ChildItem -LiteralPath $destination -File -Recurse | ForEach-Object { [IO.Path]::GetFullPath($_.FullName) })
    $unexpected = @($actualFiles | Where-Object { -not $allowedFiles.Contains($_) })
    if ($unexpected.Count) { throw "El backup contiene archivos no declarados en el manifest." }
    if ($actualFiles.Count -ne $allowedFiles.Count) { throw "El manifest declara archivos ausentes o duplicados." }

    [pscustomobject]@{ Ok=$true; Destination=$destination; Files=@($manifest.files).Count; ComparisonPackage=$comparisonPath }
}
catch {
    if (Test-Path -LiteralPath $destination) {
        Get-ChildItem -LiteralPath $destination -Force | Remove-Item -Recurse -Force
    }
    throw
}
finally {
    $plainPassword = $null
    if ($tempZip -and (Test-Path -LiteralPath $tempZip)) { Remove-Item -LiteralPath $tempZip -Force }
}
