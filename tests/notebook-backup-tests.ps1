$ErrorActionPreference = "Stop"
$projectScript = Join-Path (Split-Path $PSScriptRoot -Parent) "Backup-Jarvis.ps1"
$restoreScript = Join-Path (Split-Path $PSScriptRoot -Parent) "Restore-JarvisNotebookBackup.ps1"
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("jarvis-notebook-backup-test-" + [guid]::NewGuid().ToString("N"))
$fakeProject = Join-Path $testRoot "project"
$output = Join-Path $testRoot "output"
$restoreOne = Join-Path $testRoot "restore-one"
$restoreTwo = Join-Path $testRoot "restore-two"
$restoreWrong = Join-Path $testRoot "restore-wrong-password"
$restoreTraversal = Join-Path $testRoot "restore-traversal"

function Assert-True($Condition, [string]$Message) { if (-not $Condition) { throw "ASSERT: $Message" } }
function Write-Utf8Json([string]$Path, $Value) { [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null; [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false)) }

try {
    [IO.Directory]::CreateDirectory((Join-Path $fakeProject "data/runtime")) | Out-Null
    Write-Utf8Json (Join-Path $fakeProject "data/identity.json") ([ordered]@{ workspace_id="workspace-test"; workspace_name="Test"; sync_secret="secret-test"; device_id="device-notebook"; device_name="Notebook"; linked_devices=@(); pairing_code="123456"; pairing_token="temporary-secret"; pairing_expires_at="2026-08-19T23:59:00" })
    Write-Utf8Json (Join-Path $fakeProject "data/records.json") @([ordered]@{ id="r1"; text="café ☕"; deleted_at=$null })
    Write-Utf8Json (Join-Path $fakeProject "data/finance/movements.json") @([ordered]@{ id="m1"; amount=12.5 })
    Write-Utf8Json (Join-Path $fakeProject "data/sync/changes.json") @([ordered]@{ change_id="c1"; workspace_id="workspace-test"; entity="records"; entity_id="r1"; applied_at="2026-08-19T00:00:00" })
    Write-Utf8Json (Join-Path $fakeProject "data/sync/conflicts.json") @()
    Set-Content -LiteralPath (Join-Path $fakeProject "data/runtime/jarvis-web.pid") -Value "99999" -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $fakeProject "data/debug.log") -Value "no incluir" -Encoding UTF8

    $password = ConvertTo-SecureString "contraseña-notebook-123" -AsPlainText -Force
    $first = & $projectScript -ProjectRoot $fakeProject -OutputDirectory $output -Password $password
    Assert-True $first.Encrypted "el backup predeterminado debe estar cifrado"
    Assert-True (Test-Path -LiteralPath $first.Path) "debe existir el backup cifrado"
    Assert-True (-not (Test-Path -LiteralPath ([IO.Path]::ChangeExtension($first.Path, ".zip")))) "no debe quedar ZIP temporal junto al cifrado"

    $restored = & $restoreScript -BackupPath $first.Path -DestinationDirectory $restoreOne -Password $password
    Assert-True $restored.Ok "restauracion temporal cifrada"
    Assert-True (Test-Path -LiteralPath (Join-Path $restoreOne "data/records.json")) "incluye registros"
    Assert-True (Test-Path -LiteralPath (Join-Path $restoreOne "data/identity.json")) "incluye identidad"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $restoreOne "data/runtime/jarvis-web.pid"))) "excluye PID/runtime"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $restoreOne "data/debug.log"))) "excluye logs"
    Assert-True (Test-Path -LiteralPath $restored.ComparisonPackage) "incluye paquete comparable"
    $restoredIdentity = Get-Content -LiteralPath (Join-Path $restoreOne "data/identity.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True (-not ($restoredIdentity.PSObject.Properties.Name -contains "pairing_code")) "excluye codigo temporal de vinculacion"
    Assert-True (-not ($restoredIdentity.PSObject.Properties.Name -contains "pairing_token")) "excluye token temporal de vinculacion"
    if ($env:JARVIS_TEST_NODE -and (Test-Path -LiteralPath $env:JARVIS_TEST_NODE)) {
        & $env:JARVIS_TEST_NODE (Join-Path $PSScriptRoot "validate-backup-package.js") $restored.ComparisonPackage
        Assert-True ($LASTEXITCODE -eq 0) "el paquete de notebook debe validar en el comparador web"
    }

    $manifest = Get-Content -LiteralPath (Join-Path $restoreOne "manifest.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True (-not ($manifest.PSObject.Properties.Name -contains "project_root")) "el manifest no expone la ruta completa del perfil"
    Assert-True ((Get-FileHash -LiteralPath $restored.ComparisonPackage -Algorithm SHA256).Hash.ToLowerInvariant() -eq $manifest.comparison_sha256) "hash del paquete comparable"
    foreach ($file in @($manifest.files)) {
        $path = Join-Path $restoreOne $file.path
        Assert-True ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq $file.sha256) "hash valido para $($file.path)"
    }

    $second = & $projectScript -ProjectRoot $fakeProject -OutputDirectory $output -Password $password
    Assert-True ($second.Path -ne $first.Path) "no sobrescribe backups anteriores"
    Assert-True (Test-Path -LiteralPath $first.Path) "conserva backup anterior"
    $firstWrapper = Get-Content -LiteralPath $first.Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $secondWrapper = Get-Content -LiteralPath $second.Path -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($firstWrapper.kdf.salt -ne $secondWrapper.kdf.salt) "usa un salt nuevo por backup"
    Assert-True ($firstWrapper.cipher.iv -ne $secondWrapper.cipher.iv) "no reutiliza IV entre backups"

    $plain = & $projectScript -ProjectRoot $fakeProject -OutputDirectory $output -AllowUnencrypted
    Assert-True (-not $plain.Encrypted) "modo avanzado sin cifrar"
    Assert-True $plain.Path.EndsWith(".zip") "backup sin cifrar es ZIP"
    $plainRestore = & $restoreScript -BackupPath $plain.Path -DestinationDirectory $restoreTwo
    Assert-True $plainRestore.Ok "restauracion ZIP temporal"
    Assert-True ($plainRestore.Files -eq $restored.Files) "conteos coinciden"

    $badDestination = Join-Path $testRoot "not-empty"; [IO.Directory]::CreateDirectory($badDestination) | Out-Null; Set-Content -LiteralPath (Join-Path $badDestination "keep.txt") -Value "keep"
    $failed = $false; try { & $restoreScript -BackupPath $plain.Path -DestinationDirectory $badDestination | Out-Null } catch { $failed = $true }
    Assert-True $failed "no restaura sobre directorio no vacio"
    Assert-True (Test-Path -LiteralPath (Join-Path $badDestination "keep.txt")) "no borra contenido ajeno"

    $wrongPassword = ConvertTo-SecureString "contraseña-incorrecta-999" -AsPlainText -Force
    $failed = $false; try { & $restoreScript -BackupPath $first.Path -DestinationDirectory $restoreWrong -Password $wrongPassword | Out-Null } catch { $failed = $true }
    Assert-True $failed "rechaza contraseña incorrecta"
    Assert-True (@(Get-ChildItem -LiteralPath $restoreWrong -Force -ErrorAction SilentlyContinue).Count -eq 0) "contraseña incorrecta no restaura parcialmente"

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $maliciousZip = Join-Path $output "malicious-path-traversal.zip"
    $archive = [IO.Compression.ZipFile]::Open($maliciousZip, [IO.Compression.ZipArchiveMode]::Create)
    try {
        $entry = $archive.CreateEntry("../outside.txt")
        $writer = [IO.StreamWriter]::new($entry.Open())
        try { $writer.Write("no debe salir") } finally { $writer.Dispose() }
    } finally { $archive.Dispose() }
    $outsidePath = Join-Path $testRoot "outside.txt"
    $failed = $false; try { & $restoreScript -BackupPath $maliciousZip -DestinationDirectory $restoreTraversal | Out-Null } catch { $failed = $true }
    Assert-True $failed "rechaza path traversal"
    Assert-True (-not (Test-Path -LiteralPath $outsidePath)) "path traversal no escribe fuera del destino"

    Write-Host "notebook-backup-tests: 23 escenarios OK"
} finally {
    if (Test-Path -LiteralPath $testRoot) {
        $resolved = [IO.Path]::GetFullPath($testRoot)
        if ($resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf).StartsWith("jarvis-notebook-backup-test-")) {
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
}
