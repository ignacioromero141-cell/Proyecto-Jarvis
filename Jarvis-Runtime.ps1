function Get-JarvisRuntimePaths {
    param([string]$ProjectRoot, [int]$Port)

    $runtimeDirectory = Join-Path $ProjectRoot "data\runtime"
    $suffix = if ($Port -eq 8765) { "" } else { "-$Port" }
    return [pscustomobject]@{
        RuntimeDirectory = $runtimeDirectory
        PidFile = Join-Path $runtimeDirectory "jarvis-web$suffix.pid"
        InstanceFile = Join-Path $runtimeDirectory "jarvis-web$suffix.instance.json"
    }
}

function Get-JarvisStartMutexName {
    param([string]$ProjectRoot, [int]$Port)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes("$([System.IO.Path]::GetFullPath($ProjectRoot).ToLowerInvariant())|$Port")
        $hash = ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").Substring(0, 20)
        return "Local\Jarvis-Web-Start-$hash"
    }
    finally {
        $sha.Dispose()
    }
}

function Get-JarvisListenerPid {
    param([int]$Port)

    try {
        $connection = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($connection -and $connection.OwningProcess) { return [int]$connection.OwningProcess }
    }
    catch {}

    try {
        foreach ($line in @(netstat -ano -p tcp 2>$null | Select-String "LISTENING")) {
            $parts = (($line.Line -replace "\s+", " ").Trim()).Split(" ")
            if ($parts.Count -ge 5 -and $parts[1] -match ":$Port$") { return [int]$parts[4] }
        }
    }
    catch {}
    return $null
}

function Invoke-JarvisHealthCheck {
    param([int]$Port, [int]$TimeoutMilliseconds = 1000)

    $client = $null
    $stream = $null
    try {
        $client = [System.Net.Sockets.TcpClient]::new()
        $connect = $client.BeginConnect("127.0.0.1", $Port, $null, $null)
        if (-not $connect.AsyncWaitHandle.WaitOne($TimeoutMilliseconds)) { return $null }
        $client.EndConnect($connect)
        $client.ReceiveTimeout = $TimeoutMilliseconds
        $client.SendTimeout = $TimeoutMilliseconds
        $stream = $client.GetStream()
        $request = [System.Text.Encoding]::ASCII.GetBytes("GET /api/health HTTP/1.1`r`nHost: 127.0.0.1`r`nConnection: close`r`n`r`n")
        $stream.Write($request, 0, $request.Length)
        $memory = [System.IO.MemoryStream]::new()
        $buffer = New-Object byte[] 4096
        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $memory.Write($buffer, 0, $read)
            if ($memory.Length -gt 65536) { return $null }
        }
        $text = [System.Text.Encoding]::UTF8.GetString($memory.ToArray())
        if (-not $text.StartsWith("HTTP/1.1 200")) { return $null }
        $separator = $text.IndexOf("`r`n`r`n")
        if ($separator -lt 0) { return $null }
        return ConvertFrom-Json -InputObject $text.Substring($separator + 4)
    }
    catch { return $null }
    finally {
        if ($null -ne $stream) { try { $stream.Dispose() } catch {} }
        if ($null -ne $client) { try { $client.Dispose() } catch {} }
    }
}

function Get-JarvisInstanceMetadata {
    param([string]$InstanceFile)

    if (-not (Test-Path -LiteralPath $InstanceFile)) { return $null }
    try { return ConvertFrom-Json -InputObject (Get-Content -LiteralPath $InstanceFile -Raw) } catch { return $null }
}

function Get-JarvisProcessCommandLine {
    param([int]$ProcessId)
    try { return [string](Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction Stop).CommandLine } catch { return "" }
}

function Test-JarvisOwnedListener {
    param([string]$ProjectRoot, [int]$Port, [int]$ListenerPid, $Health, $Metadata)

    $root = [System.IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
    if ($Health -and $Health.ok -and $Health.service -eq "jarvis-web" -and [int]$Health.pid -eq $ListenerPid -and [int]$Health.port -eq $Port) {
        return [pscustomobject]@{ Owned = $true; Evidence = "health" }
    }
    if (-not $Metadata -or [int]$Metadata.pid -ne $ListenerPid -or [int]$Metadata.port -ne $Port) {
        return [pscustomobject]@{ Owned = $false; Evidence = "metadata-mismatch" }
    }
    if ([System.IO.Path]::GetFullPath([string]$Metadata.project_root).TrimEnd('\') -ne $root) {
        return [pscustomobject]@{ Owned = $false; Evidence = "project-mismatch" }
    }

    $process = Get-Process -Id $ListenerPid -ErrorAction SilentlyContinue
    if (-not $process -or $process.ProcessName -notin @("powershell", "pwsh")) {
        return [pscustomobject]@{ Owned = $false; Evidence = "process-mismatch" }
    }
    try {
        $expectedStart = [datetime]$Metadata.started_at
        $actualStart = [datetime]$process.StartTime
        if ([math]::Abs(($actualStart - $expectedStart).TotalSeconds) -gt 5) {
            return [pscustomobject]@{ Owned = $false; Evidence = "start-time-mismatch" }
        }
    }
    catch { return [pscustomobject]@{ Owned = $false; Evidence = "invalid-start-time" } }

    $commandLine = Get-JarvisProcessCommandLine -ProcessId $ListenerPid
    if (-not [string]::IsNullOrWhiteSpace($commandLine)) {
        if ($commandLine -notmatch [regex]::Escape((Join-Path $root "jarvis-web.ps1"))) {
            return [pscustomobject]@{ Owned = $false; Evidence = "command-line-mismatch" }
        }
        return [pscustomobject]@{ Owned = $true; Evidence = "metadata-and-command-line" }
    }
    return [pscustomobject]@{ Owned = $true; Evidence = "metadata-and-process-start" }
}

function Remove-JarvisStaleRuntimeFiles {
    param($Paths)
    Remove-Item -LiteralPath $Paths.PidFile -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $Paths.InstanceFile -Force -ErrorAction SilentlyContinue
}
