# Capa web: recibe pedidos HTTP y los conecta con el core.
# No contiene reglas de negocio; solo rutas, respuestas y arranque del servidor.

. (Join-Path $PSScriptRoot "..\core\records.ps1")
. (Join-Path $PSScriptRoot "..\modules\finance\finance-summary.ps1")
. (Join-Path $PSScriptRoot "..\core\sync.ps1")

Add-Type -AssemblyName System.Web

function Test-JarvisClientDisconnect {
    param($ErrorRecord)

    $message = ""
    if ($null -ne $ErrorRecord) {
        $message = $ErrorRecord.Exception.Message
        if ($null -ne $ErrorRecord.Exception.InnerException) {
            $message = "$message $($ErrorRecord.Exception.InnerException.Message)"
        }
    }

    return $ErrorRecord.Exception -is [System.IO.IOException] -or
        $ErrorRecord.Exception -is [System.Net.Sockets.SocketException] -or
        $ErrorRecord.Exception -is [System.ObjectDisposedException] -or
        $message -match "conexi[oó]n.*(anulad|cerrad|restablecid|forzosamente)" -or
        $message -match "transport" -or
        $message -match "broken pipe" -or
        $message -match "connection.*(aborted|reset|closed)"
}

function Write-JarvisStream {
    param(
        [System.Net.Sockets.NetworkStream]$Stream,
        [byte[]]$Bytes
    )

    try {
        $Stream.Write($Bytes, 0, $Bytes.Length)
        return $true
    }
    catch {
        if (Test-JarvisClientDisconnect -ErrorRecord $_) {
            return $false
        }

        throw
    }
}

function Send-JarvisResponse {
    param(
        [System.Net.Sockets.NetworkStream]$Stream,
        [int]$StatusCode,
        [string]$ContentType,
        [string]$Body
    )

    $reason = if ($StatusCode -eq 200) { "OK" } elseif ($StatusCode -eq 404) { "Not Found" } else { "Error" }
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
    $header = "HTTP/1.1 $StatusCode $reason`r`nContent-Type: $ContentType; charset=utf-8`r`nContent-Length: $($bodyBytes.Length)`r`nAccess-Control-Allow-Origin: *`r`nAccess-Control-Allow-Methods: GET, POST, OPTIONS`r`nAccess-Control-Allow-Headers: Content-Type, X-Jarvis-Workspace-Id, X-Jarvis-Device-Id, X-Jarvis-Sync-Secret`r`nConnection: close`r`n`r`n"
    $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
    if (-not (Write-JarvisStream -Stream $Stream -Bytes $headerBytes)) {
        return $false
    }
    return Write-JarvisStream -Stream $Stream -Bytes $bodyBytes
}

function Send-JarvisJson {
    param(
        [System.Net.Sockets.NetworkStream]$Stream,
        [int]$StatusCode,
        $Value
    )

    $json = ConvertTo-Json -InputObject $Value -Depth 8
    Send-JarvisResponse -Stream $Stream -StatusCode $StatusCode -ContentType "application/json" -Body $json
}

function Send-JarvisTextFile {
    param(
        [System.Net.Sockets.NetworkStream]$Stream,
        [string]$Path,
        [string]$ContentType
    )

    $body = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    Send-JarvisResponse -Stream $Stream -StatusCode 200 -ContentType $ContentType -Body $body
}

function Send-JarvisBinaryFile {
    param(
        [System.Net.Sockets.NetworkStream]$Stream,
        [string]$Path,
        [string]$ContentType
    )

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $header = "HTTP/1.1 200 OK`r`nContent-Type: $ContentType`r`nContent-Length: $($bytes.Length)`r`nAccess-Control-Allow-Origin: *`r`nAccess-Control-Allow-Methods: GET, POST, OPTIONS`r`nAccess-Control-Allow-Headers: Content-Type, X-Jarvis-Workspace-Id, X-Jarvis-Device-Id, X-Jarvis-Sync-Secret`r`nConnection: close`r`n`r`n"
    $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
    if (-not (Write-JarvisStream -Stream $Stream -Bytes $headerBytes)) {
        return $false
    }
    return Write-JarvisStream -Stream $Stream -Bytes $bytes
}

function Read-JarvisRequest {
    param([System.Net.Sockets.TcpClient]$Client)

    $stream = $Client.GetStream()
    $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8, $false, 4096, $true)
    $requestLine = $reader.ReadLine()
    if ([string]::IsNullOrWhiteSpace($requestLine)) {
        return $null
    }

    $headers = @{}
    while ($true) {
        $line = $reader.ReadLine()
        if ($null -eq $line -or $line -eq "") {
            break
        }

        $parts = $line.Split(":", 2)
        if ($parts.Count -eq 2) {
            $headers[$parts[0].Trim().ToLowerInvariant()] = $parts[1].Trim()
        }
    }

    $body = ""
    if ($headers.ContainsKey("content-length")) {
        $length = [int]$headers["content-length"]
        if ($length -gt 0) {
            $buffer = New-Object char[] $length
            [void]$reader.ReadBlock($buffer, 0, $length)
            $body = -join $buffer
        }
    }

    $parts = $requestLine.Split(" ")
    return [pscustomobject]@{
        method = $parts[0]
        target = $parts[1]
        body = $body
        headers = $headers
        stream = $stream
    }
}

function Get-JarvisJsonBody {
    param([string]$Body)

    if ([string]::IsNullOrWhiteSpace($Body)) {
        return [pscustomobject]@{}
    }

    return ConvertFrom-Json -InputObject $Body
}

function Get-JarvisQueryValue {
    param(
        [string]$Target,
        [string]$Name
    )

    $uri = [uri]"http://localhost$Target"
    $query = [System.Web.HttpUtility]::ParseQueryString($uri.Query)
    return $query[$Name]
}

function Get-JarvisRequestHeader {
    param(
        $Request,
        [string]$Name
    )

    $key = $Name.ToLowerInvariant()
    if ($Request.headers -and $Request.headers.ContainsKey($key)) {
        return $Request.headers[$key]
    }

    return ""
}

function Test-JarvisRequestSyncAuth {
    param(
        $Request,
        $Body = $null
    )

    $workspaceId = Get-JarvisRequestHeader -Request $Request -Name "X-Jarvis-Workspace-Id"
    $deviceId = Get-JarvisRequestHeader -Request $Request -Name "X-Jarvis-Device-Id"
    $secret = Get-JarvisRequestHeader -Request $Request -Name "X-Jarvis-Sync-Secret"

    if ($Body) {
        $workspaceId = Get-JarvisSafeText -Value $workspaceId -Fallback (Get-JarvisSafeText -Value $Body.workspace_id)
        $deviceId = Get-JarvisSafeText -Value $deviceId -Fallback (Get-JarvisSafeText -Value $Body.device_id)
        $secret = Get-JarvisSafeText -Value $secret -Fallback (Get-JarvisSafeText -Value $Body.sync_secret)
    }

    return Test-JarvisSyncAuth -WorkspaceId $workspaceId -DeviceId $deviceId -SyncSecret $secret
}

function Handle-JarvisPageRoute {
    param(
        $Request,
        [string]$Path
    )

    if ($Request.method -eq "GET" -and $Path -eq "/") {
        Send-JarvisTextFile -Stream $Request.stream -Path (Join-Path $PSScriptRoot "static\index.html") -ContentType "text/html"
        return $true
    }

    if ($Request.method -eq "GET" -and $Path -eq "/finance") {
        Send-JarvisTextFile -Stream $Request.stream -Path (Join-Path $PSScriptRoot "static\finance.html") -ContentType "text/html"
        return $true
    }

    if ($Request.method -eq "GET" -and $Path -eq "/organization") {
        Send-JarvisTextFile -Stream $Request.stream -Path (Join-Path $PSScriptRoot "static\organization.html") -ContentType "text/html"
        return $true
    }

    if ($Request.method -eq "GET" -and $Path -eq "/settings") {
        Send-JarvisTextFile -Stream $Request.stream -Path (Join-Path $PSScriptRoot "static\settings.html") -ContentType "text/html"
        return $true
    }

    return $false
}

function Handle-JarvisStaticRoute {
    param(
        $Request,
        [string]$Path
    )

    if ($Request.method -ne "GET") {
        return $false
    }

    $staticDirectory = Join-Path $PSScriptRoot "static"
    $routes = @{
        "/manifest.webmanifest" = @{ file = "manifest.webmanifest"; type = "application/manifest+json" }
        "/index.html" = @{ file = "index.html"; type = "text/html" }
        "/finance.html" = @{ file = "finance.html"; type = "text/html" }
        "/organization.html" = @{ file = "organization.html"; type = "text/html" }
        "/settings.html" = @{ file = "settings.html"; type = "text/html" }
        "/service-worker.js" = @{ file = "service-worker.js"; type = "application/javascript" }
        "/jarvis-theme.css" = @{ file = "jarvis-theme.css"; type = "text/css" }
        "/jarvis-local-store.js" = @{ file = "jarvis-local-store.js"; type = "application/javascript" }
        "/jarvis-shared.js" = @{ file = "jarvis-shared.js"; type = "application/javascript" }
        "/icons/icon.svg" = @{ file = "icons\icon.svg"; type = "image/svg+xml" }
        "/icons/maskable.svg" = @{ file = "icons\maskable.svg"; type = "image/svg+xml" }
        "/icons/icon-192.png" = @{ file = "icons\icon-192.png"; type = "image/png"; binary = $true }
        "/icons/icon-512.png" = @{ file = "icons\icon-512.png"; type = "image/png"; binary = $true }
        "/icons/apple-touch-icon.png" = @{ file = "icons\apple-touch-icon.png"; type = "image/png"; binary = $true }
        "/static/jarvis-theme.css" = @{ file = "jarvis-theme.css"; type = "text/css" }
        "/static/jarvis-local-store.js" = @{ file = "jarvis-local-store.js"; type = "application/javascript" }
        "/static/jarvis-shared.js" = @{ file = "jarvis-shared.js"; type = "application/javascript" }
        "/static/icons/icon.svg" = @{ file = "icons\icon.svg"; type = "image/svg+xml" }
        "/static/icons/maskable.svg" = @{ file = "icons\maskable.svg"; type = "image/svg+xml" }
        "/static/icons/icon-192.png" = @{ file = "icons\icon-192.png"; type = "image/png"; binary = $true }
        "/static/icons/icon-512.png" = @{ file = "icons\icon-512.png"; type = "image/png"; binary = $true }
        "/static/icons/apple-touch-icon.png" = @{ file = "icons\apple-touch-icon.png"; type = "image/png"; binary = $true }
    }

    if (-not $routes.ContainsKey($Path)) {
        return $false
    }

    $route = $routes[$Path]
    $filePath = Join-Path $staticDirectory $route.file
    if (-not (Test-Path -LiteralPath $filePath)) {
        Send-JarvisJson -Stream $Request.stream -StatusCode 404 -Value @{ ok = $false; error = "Archivo estatico no encontrado." }
        return $true
    }

    if ($route.binary) {
        Send-JarvisBinaryFile -Stream $Request.stream -Path $filePath -ContentType $route.type
    }
    else {
        Send-JarvisTextFile -Stream $Request.stream -Path $filePath -ContentType $route.type
    }
    return $true
}

function Handle-JarvisRecordsApiRoute {
    param(
        $Request,
        [string]$Path
    )

    if ($Request.method -eq "GET" -and $Path -eq "/api/records") {
        Send-JarvisJson -Stream $Request.stream -StatusCode 200 -Value @{ ok = $true; records = @(Get-JarvisVisibleRecords); summary = (Get-JarvisDashboardSummary) }
        return $true
    }

    if ($Request.method -eq "POST" -and $Path -eq "/api/records") {
        $body = Get-JarvisJsonBody -Body $Request.body
        Add-JarvisRecord `
            -Type $body.type `
            -Text $body.text `
            -Title (Get-JarvisSafeText -Value $body.title) `
            -Description (Get-JarvisSafeText -Value $body.description) `
            -Priority (Get-JarvisSafeText -Value $body.priority) `
            -DueDate (Get-JarvisSafeText -Value $body.due_date) `
            -Tags $body.tags | Out-Null
        Send-JarvisJson -Stream $Request.stream -StatusCode 200 -Value @{ ok = $true; records = @(Get-JarvisVisibleRecords) }
        return $true
    }

    if ($Request.method -eq "POST" -and $Path -eq "/api/records/update") {
        $body = Get-JarvisJsonBody -Body $Request.body
        Update-JarvisRecord `
            -Id $body.id `
            -Type $body.type `
            -Text $body.text `
            -Title (Get-JarvisSafeText -Value $body.title) `
            -Description (Get-JarvisSafeText -Value $body.description) `
            -Priority (Get-JarvisSafeText -Value $body.priority) `
            -DueDate (Get-JarvisSafeText -Value $body.due_date) `
            -Tags $body.tags | Out-Null
        Send-JarvisJson -Stream $Request.stream -StatusCode 200 -Value @{ ok = $true; records = @(Get-JarvisVisibleRecords) }
        return $true
    }

    if ($Request.method -eq "POST" -and $Path -eq "/api/records/status") {
        $body = Get-JarvisJsonBody -Body $Request.body
        Set-JarvisTaskStatus -Id $body.id -Status $body.status | Out-Null
        Send-JarvisJson -Stream $Request.stream -StatusCode 200 -Value @{ ok = $true; records = @(Get-JarvisVisibleRecords) }
        return $true
    }

    if ($Request.method -eq "POST" -and $Path -eq "/api/quick") {
        $body = Get-JarvisJsonBody -Body $Request.body
        $capture = Get-JarvisQuickCapture -Text $body.text
        Add-JarvisRecord -Type $capture.type -Text $capture.text | Out-Null
        Send-JarvisJson -Stream $Request.stream -StatusCode 200 -Value @{ ok = $true; records = @(Get-JarvisVisibleRecords) }
        return $true
    }

    if ($Request.method -eq "POST" -and $Path -eq "/api/complete") {
        $body = Get-JarvisJsonBody -Body $Request.body
        Complete-JarvisTask -Id $body.id
        Send-JarvisJson -Stream $Request.stream -StatusCode 200 -Value @{ ok = $true; records = @(Get-JarvisVisibleRecords) }
        return $true
    }

    if ($Request.method -eq "POST" -and $Path -eq "/api/delete") {
        $body = Get-JarvisJsonBody -Body $Request.body
        Remove-JarvisRecord -Id $body.id
        Send-JarvisJson -Stream $Request.stream -StatusCode 200 -Value @{ ok = $true; records = @(Get-JarvisVisibleRecords) }
        return $true
    }

    if ($Request.method -eq "POST" -and $Path -eq "/api/backup") {
        $backup = New-JarvisDataBackup -Reason "web-manual"
        Send-JarvisJson -Stream $Request.stream -StatusCode 200 -Value @{ ok = $true; file = (Split-Path -Path $backup -Leaf) }
        return $true
    }

    return $false
}

function Handle-JarvisFinanceApiRoute {
    param(
        $Request,
        [string]$Path
    )

    if ($Request.method -eq "GET" -and $Path -eq "/api/finance/summary") {
        $month = Get-JarvisQueryValue -Target $Request.target -Name "month"
        if ([string]::IsNullOrWhiteSpace($month)) {
            $month = Get-FinanceMonthKey
        }

        Send-JarvisJson -Stream $Request.stream -StatusCode 200 -Value @{
            ok = $true
            movements = @(Get-FinanceVisibleMovements)
            categories = @(Read-FinanceCategories)
            priorities = @(Read-FinancePriorities)
            summary = (Get-FinanceMonthlySummary -Month $month)
        }
        return $true
    }

    if ($Request.method -eq "POST" -and $Path -eq "/api/finance/movements") {
        $body = Get-JarvisJsonBody -Body $Request.body
        Add-FinanceMovement `
            -Kind $body.kind `
            -CategoryId $body.category_id `
            -Priority $body.priority `
            -Amount ([decimal]$body.amount) `
            -Date $body.date `
            -Note (Get-FinanceSafeText -Value $body.note) `
            -PaymentMethod (Get-FinanceSafeText -Value $body.payment_method) | Out-Null
        Send-JarvisJson -Stream $Request.stream -StatusCode 200 -Value @{ ok = $true; movements = @(Get-FinanceVisibleMovements) }
        return $true
    }

    if ($Request.method -eq "POST" -and $Path -eq "/api/finance/delete") {
        $body = Get-JarvisJsonBody -Body $Request.body
        Remove-FinanceMovement -Id $body.id
        Send-JarvisJson -Stream $Request.stream -StatusCode 200 -Value @{ ok = $true; movements = @(Get-FinanceVisibleMovements) }
        return $true
    }

    if ($Request.method -eq "POST" -and $Path -eq "/api/finance/targets") {
        $body = Get-JarvisJsonBody -Body $Request.body
        $targets = Set-FinanceTargets `
            -Saving ([decimal]$body.saving) `
            -Necessary ([decimal]$body.necessary) `
            -Optional ([decimal]$body.optional) `
            -PersonalInvestment ([decimal]$body.personal_investment)
        Send-JarvisJson -Stream $Request.stream -StatusCode 200 -Value @{ ok = $true; targets = $targets }
        return $true
    }

    return $false
}

function Get-JarvisBootstrapSnapshot {
    return [pscustomobject]@{
        schema_version = 1
        generated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
        source = "notebook-json"
        identity = Get-JarvisIdentityPublic
        records = @(Read-JarvisRecords)
        finance = [pscustomobject]@{
            movements = @(Read-FinanceMovements)
            categories = @(Read-FinanceCategories)
            priorities = @(Read-FinancePriorities)
            settings = Read-FinanceSettings
        }
    }
}

function Handle-JarvisBootstrapApiRoute {
    param(
        $Request,
        [string]$Path
    )

    if ($Request.method -eq "GET" -and $Path -eq "/api/bootstrap/export") {
        $auth = Test-JarvisRequestSyncAuth -Request $Request
        if (-not $auth.ok) {
            Send-JarvisJson -Stream $Request.stream -StatusCode $auth.status -Value @{ ok = $false; error = $auth.error }
            return $true
        }
        Send-JarvisJson -Stream $Request.stream -StatusCode 200 -Value @{ ok = $true; snapshot = (Get-JarvisBootstrapSnapshot) }
        return $true
    }

    return $false
}

function Handle-JarvisSyncApiRoute {
    param(
        $Request,
        [string]$Path
    )

    if ($Request.method -eq "GET" -and $Path -eq "/api/sync/status") {
        Send-JarvisJson -Stream $Request.stream -StatusCode 200 -Value @{ ok = $true; status = (Get-JarvisSyncStatus) }
        return $true
    }

    if ($Request.method -eq "POST" -and $Path -eq "/api/sync/settings") {
        $body = Get-JarvisJsonBody -Body $Request.body
        if (-not [string]::IsNullOrWhiteSpace((Get-JarvisSafeText -Value $body.workspace_name))) {
            Set-JarvisWorkspaceName -WorkspaceName $body.workspace_name | Out-Null
        }
        if (-not [string]::IsNullOrWhiteSpace((Get-JarvisSafeText -Value $body.device_name))) {
            Set-JarvisDeviceName -DeviceName $body.device_name | Out-Null
        }
        Send-JarvisJson -Stream $Request.stream -StatusCode 200 -Value @{ ok = $true; status = (Get-JarvisSyncStatus) }
        return $true
    }

    if ($Request.method -eq "POST" -and $Path -eq "/api/sync/pairing/start") {
        Send-JarvisJson -Stream $Request.stream -StatusCode 200 -Value @{ ok = $true; pairing = (New-JarvisPairingCode) }
        return $true
    }

    if ($Request.method -eq "POST" -and $Path -eq "/api/sync/pairing/complete") {
        $body = Get-JarvisJsonBody -Body $Request.body
        $paired = Complete-JarvisPairing -PairingCode $body.pairing_code -DeviceId $body.device_id -DeviceName (Get-JarvisSafeText -Value $body.device_name -Fallback "Dispositivo vinculado")
        Send-JarvisJson -Stream $Request.stream -StatusCode 200 -Value @{
            ok = $true
            workspace_id = $paired.workspace_id
            workspace_name = $paired.workspace_name
            sync_secret = $paired.sync_secret
            linked_devices = @($paired.linked_devices)
        }
        return $true
    }

    if ($Request.method -eq "GET" -and $Path -eq "/api/sync/changes") {
        $auth = Test-JarvisRequestSyncAuth -Request $Request
        if (-not $auth.ok) {
            Send-JarvisJson -Stream $Request.stream -StatusCode $auth.status -Value @{ ok = $false; error = $auth.error }
            return $true
        }
        $since = Get-JarvisQueryValue -Target $Request.target -Name "since"
        $excludeDeviceId = Get-JarvisQueryValue -Target $Request.target -Name "exclude_device_id"
        Send-JarvisJson -Stream $Request.stream -StatusCode 200 -Value @{
            ok = $true
            device_id = Get-JarvisDeviceId
            workspace_id = Get-JarvisWorkspaceId
            generated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
            changes = @(Get-JarvisSyncChangesSince -Since $since -ExcludeDeviceId $excludeDeviceId)
        }
        return $true
    }

    if ($Request.method -eq "POST" -and $Path -eq "/api/sync/apply") {
        $body = Get-JarvisJsonBody -Body $Request.body
        $auth = Test-JarvisRequestSyncAuth -Request $Request -Body $body
        if (-not $auth.ok) {
            Send-JarvisJson -Stream $Request.stream -StatusCode $auth.status -Value @{ ok = $false; error = $auth.error }
            return $true
        }
        $incomingChanges = @($body.changes)
        $remoteDeviceId = Get-JarvisSafeText -Value $body.device_id
        $remoteDeviceName = Get-JarvisSafeText -Value $body.device_name
        Update-JarvisLinkedDeviceSeen -DeviceId $remoteDeviceId -DeviceName $remoteDeviceName | Out-Null
        $since = Get-JarvisSafeText -Value $body.since
        $results = @(Apply-JarvisSyncChanges -Changes $incomingChanges -RemoteDeviceId $remoteDeviceId)
        $acceptedChangeIds = @($results | Where-Object { @("accepted", "skipped") -contains $_.status } | ForEach-Object { $_.change_id })

        Send-JarvisJson -Stream $Request.stream -StatusCode 200 -Value @{
            ok = $true
            device_id = Get-JarvisDeviceId
            workspace_id = Get-JarvisWorkspaceId
            generated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
            accepted_change_ids = $acceptedChangeIds
            results = $results
            changes = @(Get-JarvisSyncChangesSince -Since $since -ExcludeDeviceId $remoteDeviceId)
            linked_devices = @((Read-JarvisIdentity).linked_devices)
            status = (Get-JarvisSyncStatus)
        }
        return $true
    }

    if ($Request.method -eq "GET" -and $Path -eq "/api/sync/conflicts") {
        Send-JarvisJson -Stream $Request.stream -StatusCode 200 -Value @{ ok = $true; conflicts = @(Read-JarvisSyncConflicts) }
        return $true
    }

    if ($Request.method -eq "POST" -and $Path -eq "/api/sync/conflicts/resolve") {
        $body = Get-JarvisJsonBody -Body $Request.body
        $conflicts = Resolve-JarvisSyncConflict -ConflictId $body.conflict_id -Resolution (Get-JarvisSafeText -Value $body.resolution -Fallback "local")
        Send-JarvisJson -Stream $Request.stream -StatusCode 200 -Value @{ ok = $true; conflicts = @($conflicts) }
        return $true
    }

    return $false
}

function Handle-JarvisRequest {
    param($Request)

    $path = ([uri]"http://localhost$($Request.target)").AbsolutePath
    try {
        if ($Request.method -eq "OPTIONS") {
            Send-JarvisResponse -Stream $Request.stream -StatusCode 200 -ContentType "text/plain" -Body ""
            return
        }
        if (Handle-JarvisStaticRoute -Request $Request -Path $path) { return }
        if (Handle-JarvisPageRoute -Request $Request -Path $path) { return }
        if (Handle-JarvisRecordsApiRoute -Request $Request -Path $path) { return }
        if (Handle-JarvisFinanceApiRoute -Request $Request -Path $path) { return }
        if (Handle-JarvisBootstrapApiRoute -Request $Request -Path $path) { return }
        if (Handle-JarvisSyncApiRoute -Request $Request -Path $path) { return }

        Send-JarvisJson -Stream $Request.stream -StatusCode 404 -Value @{ ok = $false; error = "Ruta no encontrada." }
    }
    catch {
        if (Test-JarvisClientDisconnect -ErrorRecord $_) {
            return
        }

        try {
            Send-JarvisJson -Stream $Request.stream -StatusCode 500 -Value @{ ok = $false; error = $_.Exception.Message } | Out-Null
        }
        catch {
            if (-not (Test-JarvisClientDisconnect -ErrorRecord $_)) {
                throw
            }
        }
    }
}

function Get-JarvisLocalAddresses {
    param([int]$Port)

    $addresses = @("http://localhost:$Port")
    try {
        $hostEntry = [System.Net.Dns]::GetHostEntry([System.Net.Dns]::GetHostName())
        foreach ($address in $hostEntry.AddressList) {
            if ($address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -and
                -not $address.ToString().StartsWith("169.254")) {
                $addresses += "http://$($address.ToString()):$Port"
            }
        }
    }
    catch {}

    return @($addresses | Select-Object -Unique)
}

function Start-JarvisWebServer {
    param(
        [string]$ProjectRoot,
        [int]$Port = 8765,
        [switch]$SmokeTest
    )

    Initialize-JarvisStorage -ProjectRoot $ProjectRoot
    Initialize-FinanceStorage -ProjectRoot $ProjectRoot
    Initialize-JarvisSyncStorage

    if ($SmokeTest) {
        $html = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot "static\index.html"), [System.Text.Encoding]::UTF8)
        $financeHtml = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot "static\finance.html"), [System.Text.Encoding]::UTF8)
        $organizationHtml = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot "static\organization.html"), [System.Text.Encoding]::UTF8)
        $settingsHtml = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot "static\settings.html"), [System.Text.Encoding]::UTF8)
        $records = @(Read-JarvisRecords)
        $bootstrap = Get-JarvisBootstrapSnapshot
        [void](Get-JarvisQuickCapture -Text "tengo que estudiar")
        $syncStatus = Get-JarvisSyncStatus
        Write-Host "Jarvis web 0.5 OK. HTML: $($html.Length) Finanzas: $($financeHtml.Length) Organizacion: $($organizationHtml.Length) Configuracion: $($settingsHtml.Length) Registros: $($records.Count) Bootstrap: $(@($bootstrap.records).Count) registros SyncChanges: $($syncStatus.change_count)"
        return
    }

    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $Port)
    $listener.Start()

    Write-Host ""
    Write-Host "Jarvis web 0.5 esta funcionando." -ForegroundColor Cyan
    Write-Host "Escuchando en todas las interfaces locales: 0.0.0.0:$Port" -ForegroundColor Cyan
    Write-Host "Abrilo en esta notebook:" -ForegroundColor Cyan
    Write-Host "  http://localhost:$Port"
    Write-Host ""
    Write-Host "Si tu iPhone esta en la misma red Wi-Fi, proba alguna de estas direcciones:"
    foreach ($address in Get-JarvisLocalAddresses -Port $Port) {
        if ($address -ne "http://localhost:$Port") {
            Write-Host "  $address"
        }
    }
    Write-Host ""
    Write-Host "Para cerrar Jarvis web, volve a esta ventana y presiona Ctrl + C."
    Write-Host ""

    while ($true) {
        $client = $listener.AcceptTcpClient()
        try {
            $request = Read-JarvisRequest -Client $client
            if ($null -ne $request) {
                Handle-JarvisRequest -Request $request
            }
        }
        catch {
            if (-not (Test-JarvisClientDisconnect -ErrorRecord $_)) {
                Write-Host "Error atendiendo solicitud: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
        finally {
            try {
                $client.Close()
            }
            catch {}
        }
    }
}
