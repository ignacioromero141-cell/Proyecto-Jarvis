param(
    [switch]$SmokeTest
)

$ErrorActionPreference = "Stop"
$dataDirectory = Join-Path $PSScriptRoot "data"
$dataFile = Join-Path $dataDirectory "records.json"
$backupDirectory = Join-Path $dataDirectory "backups"

function Initialize-Storage {
    if (-not (Test-Path -LiteralPath $dataDirectory)) {
        New-Item -ItemType Directory -Path $dataDirectory | Out-Null
    }

    if (-not (Test-Path -LiteralPath $dataFile)) {
        "[]" | Set-Content -LiteralPath $dataFile -Encoding UTF8
    }

    if (-not (Test-Path -LiteralPath $backupDirectory)) {
        New-Item -ItemType Directory -Path $backupDirectory | Out-Null
    }
}

function Read-Records {
    $content = Get-Content -LiteralPath $dataFile -Raw
    if ([string]::IsNullOrWhiteSpace($content)) {
        return @()
    }

    $records = ConvertFrom-Json -InputObject $content
    return @($records | ForEach-Object { $_ })
}

function Write-Records {
    param([array]$Records)

    New-DataBackup -Reason "auto"
    ConvertTo-Json -InputObject $Records -Depth 4 |
        Set-Content -LiteralPath $dataFile -Encoding UTF8
}

function New-DataBackup {
    param([string]$Reason = "manual")

    if (-not (Test-Path -LiteralPath $dataFile)) {
        return $null
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $safeReason = $Reason -replace "[^a-zA-Z0-9_-]", "-"
    $backupFile = Join-Path $backupDirectory "records-$safeReason-$timestamp.json"
    Copy-Item -LiteralPath $dataFile -Destination $backupFile
    return $backupFile
}

function Get-SafeText {
    param(
        $Value,
        [string]$Fallback = ""
    )

    if ($null -eq $Value) {
        return $Fallback
    }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $Fallback
    }

    return $text
}

function Get-SafeDateText {
    param(
        $Value,
        [string]$Format
    )

    try {
        return ([datetime]::Parse((Get-SafeText -Value $Value -Fallback (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")))).ToString($Format)
    }
    catch {
        return "sin fecha"
    }
}

function Test-IsToday {
    param($Value)

    try {
        return ([datetime]::Parse((Get-SafeText -Value $Value))).Date -eq (Get-Date).Date
    }
    catch {
        return $false
    }
}

function Add-Record {
    param(
        [string]$Type,
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "Escribi algo antes de guardar."
    }

    $records = @(Read-Records)
    $record = [pscustomobject]@{
        id = [guid]::NewGuid().ToString("N").Substring(0, 6)
        type = $Type
        text = $Text.Trim()
        status = if ($Type -eq "tarea") { "pendiente" } else { "activo" }
        created_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
        updated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    }

    $records += $record
    Write-Records -Records $records
}

function Complete-Task {
    param([string]$Id)

    $records = @(Read-Records)
    $record = $records | Where-Object { $_.id -eq $Id -and $_.type -eq "tarea" } | Select-Object -First 1
    if (-not $record) {
        throw "Selecciona una tarea pendiente."
    }

    $record.status = "completada"
    $record.updated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    Write-Records -Records $records
}

function Remove-Record {
    param([string]$Id)

    $records = @(Read-Records)
    $remainingRecords = @($records | Where-Object { $_.id -ne $Id })
    Write-Records -Records $remainingRecords
}

function Update-RecordText {
    param(
        [string]$Id,
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "El texto no puede quedar vacio."
    }

    $records = @(Read-Records)
    $record = $records | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if (-not $record) {
        throw "No encontre el registro seleccionado."
    }

    $record.text = $Text.Trim()
    $record.updated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    Write-Records -Records $records
}

function Get-QuickCapture {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "Escribi algo antes de guardar."
    }

    $cleanText = $Text.Trim()
    $lowerText = $cleanText.ToLowerInvariant()
    $type = "idea"

    if ($lowerText -match "^(tarea|tengo que|debo|hacer|comprar|estudiar|leer)\b") {
        $type = "tarea"
    }
    elseif ($lowerText -match "^(recorda|recordar|recuerdo|dato)\b") {
        $type = "recuerdo"
    }

    $cleanText = $cleanText -replace "(?i)^(idea|tarea|recuerdo|dato)\s*:\s*", ""
    $cleanText = $cleanText -replace "(?i)^(recorda que|recordar que|recorda|recordar)\s+", ""
    $cleanText = $cleanText -replace "(?i)^(tengo que|debo)\s+", ""

    return [pscustomobject]@{
        type = $type
        text = $cleanText.Trim()
    }
}

Initialize-Storage

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic
[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object System.Windows.Forms.Form
$form.Text = "Jarvis 0.4"
$form.StartPosition = "CenterScreen"
$form.Size = New-Object System.Drawing.Size(1080, 680)
$form.MinimumSize = New-Object System.Drawing.Size(960, 600)
$form.BackColor = [System.Drawing.Color]::FromArgb(245, 247, 250)

$title = New-Object System.Windows.Forms.Label
$title.Text = "Jarvis 0.4"
$title.Font = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
$title.ForeColor = [System.Drawing.Color]::FromArgb(22, 78, 99)
$title.Location = New-Object System.Drawing.Point(24, 18)
$title.AutoSize = $true
$form.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = "Descarga una idea, tarea o recuerdo. Todo queda guardado localmente."
$subtitle.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$subtitle.Location = New-Object System.Drawing.Point(27, 57)
$subtitle.AutoSize = $true
$form.Controls.Add($subtitle)

$input = New-Object System.Windows.Forms.TextBox
$input.Location = New-Object System.Drawing.Point(30, 94)
$input.Size = New-Object System.Drawing.Size(610, 66)
$input.Multiline = $true
$input.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$form.Controls.Add($input)

$typeSelector = New-Object System.Windows.Forms.ComboBox
$typeSelector.Location = New-Object System.Drawing.Point(660, 94)
$typeSelector.Size = New-Object System.Drawing.Size(190, 28)
$typeSelector.DropDownStyle = "DropDownList"
[void]$typeSelector.Items.AddRange(@("idea", "tarea", "recuerdo"))
$typeSelector.SelectedIndex = 0
$form.Controls.Add($typeSelector)

$saveButton = New-Object System.Windows.Forms.Button
$saveButton.Text = "Guardar"
$saveButton.Location = New-Object System.Drawing.Point(660, 132)
$saveButton.Size = New-Object System.Drawing.Size(90, 30)
$saveButton.BackColor = [System.Drawing.Color]::FromArgb(22, 78, 99)
$saveButton.ForeColor = [System.Drawing.Color]::White
$saveButton.FlatStyle = "Flat"
$form.Controls.Add($saveButton)

$quickButton = New-Object System.Windows.Forms.Button
$quickButton.Text = "Captura rapida"
$quickButton.Location = New-Object System.Drawing.Point(760, 132)
$quickButton.Size = New-Object System.Drawing.Size(120, 30)
$quickButton.BackColor = [System.Drawing.Color]::FromArgb(15, 118, 110)
$quickButton.ForeColor = [System.Drawing.Color]::White
$quickButton.FlatStyle = "Flat"
$form.Controls.Add($quickButton)

$filterLabel = New-Object System.Windows.Forms.Label
$filterLabel.Text = "Mostrar:"
$filterLabel.Location = New-Object System.Drawing.Point(30, 190)
$filterLabel.AutoSize = $true
$form.Controls.Add($filterLabel)

$filterSelector = New-Object System.Windows.Forms.ComboBox
$filterSelector.Location = New-Object System.Drawing.Point(90, 186)
$filterSelector.Size = New-Object System.Drawing.Size(150, 28)
$filterSelector.DropDownStyle = "DropDownList"
[void]$filterSelector.Items.AddRange(@("todos", "ideas", "tareas", "recuerdos"))
$filterSelector.SelectedIndex = 0
$form.Controls.Add($filterSelector)

$searchLabel = New-Object System.Windows.Forms.Label
$searchLabel.Text = "Buscar:"
$searchLabel.Location = New-Object System.Drawing.Point(270, 190)
$searchLabel.AutoSize = $true
$form.Controls.Add($searchLabel)

$searchBox = New-Object System.Windows.Forms.TextBox
$searchBox.Location = New-Object System.Drawing.Point(325, 186)
$searchBox.Size = New-Object System.Drawing.Size(555, 28)
$searchBox.Anchor = "Top, Left, Right"
$form.Controls.Add($searchBox)

$list = New-Object System.Windows.Forms.ListView
$list.Location = New-Object System.Drawing.Point(30, 225)
$list.Size = New-Object System.Drawing.Size(650, 335)
$list.View = "Details"
$list.FullRowSelect = $true
$list.GridLines = $true
$list.Anchor = "Top, Bottom, Left"
[void]$list.Columns.Add("Tipo", 85)
[void]$list.Columns.Add("Estado", 90)
[void]$list.Columns.Add("Contenido", 270)
[void]$list.Columns.Add("Fecha", 130)
[void]$list.Columns.Add("Codigo", 65)
$form.Controls.Add($list)

$todayPanel = New-Object System.Windows.Forms.Panel
$todayPanel.Location = New-Object System.Drawing.Point(705, 225)
$todayPanel.Size = New-Object System.Drawing.Size(335, 335)
$todayPanel.Anchor = "Top, Bottom, Right"
$todayPanel.BackColor = [System.Drawing.Color]::White
$todayPanel.BorderStyle = "FixedSingle"
$form.Controls.Add($todayPanel)

$todayTitle = New-Object System.Windows.Forms.Label
$todayTitle.Text = "Hoy"
$todayTitle.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$todayTitle.ForeColor = [System.Drawing.Color]::FromArgb(22, 78, 99)
$todayTitle.Location = New-Object System.Drawing.Point(14, 12)
$todayTitle.AutoSize = $true
$todayPanel.Controls.Add($todayTitle)

$todayText = New-Object System.Windows.Forms.TextBox
$todayText.Location = New-Object System.Drawing.Point(16, 48)
$todayText.Size = New-Object System.Drawing.Size(300, 245)
$todayText.Anchor = "Top, Bottom, Left, Right"
$todayText.Multiline = $true
$todayText.ReadOnly = $true
$todayText.BorderStyle = "None"
$todayText.BackColor = [System.Drawing.Color]::White
$todayText.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$todayText.ScrollBars = "Vertical"
$todayPanel.Controls.Add($todayText)

$refreshButton = New-Object System.Windows.Forms.Button
$refreshButton.Text = "Actualizar"
$refreshButton.Location = New-Object System.Drawing.Point(16, 300)
$refreshButton.Size = New-Object System.Drawing.Size(300, 28)
$refreshButton.Anchor = "Bottom, Left, Right"
$todayPanel.Controls.Add($refreshButton)

$completeButton = New-Object System.Windows.Forms.Button
$completeButton.Text = "Completar tarea"
$completeButton.Location = New-Object System.Drawing.Point(30, 585)
$completeButton.Size = New-Object System.Drawing.Size(150, 32)
$completeButton.Anchor = "Bottom, Left"
$form.Controls.Add($completeButton)

$editButton = New-Object System.Windows.Forms.Button
$editButton.Text = "Editar seleccionado"
$editButton.Location = New-Object System.Drawing.Point(195, 585)
$editButton.Size = New-Object System.Drawing.Size(165, 32)
$editButton.Anchor = "Bottom, Left"
$form.Controls.Add($editButton)

$deleteButton = New-Object System.Windows.Forms.Button
$deleteButton.Text = "Borrar seleccionado"
$deleteButton.Location = New-Object System.Drawing.Point(375, 585)
$deleteButton.Size = New-Object System.Drawing.Size(165, 32)
$deleteButton.Anchor = "Bottom, Left"
$form.Controls.Add($deleteButton)

$backupButton = New-Object System.Windows.Forms.Button
$backupButton.Text = "Backup"
$backupButton.Location = New-Object System.Drawing.Point(555, 585)
$backupButton.Size = New-Object System.Drawing.Size(95, 32)
$backupButton.Anchor = "Bottom, Left"
$form.Controls.Add($backupButton)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = "Listo."
$statusLabel.Location = New-Object System.Drawing.Point(670, 593)
$statusLabel.Size = New-Object System.Drawing.Size(370, 24)
$statusLabel.Anchor = "Bottom, Left, Right"
$form.Controls.Add($statusLabel)

function Refresh-List {
    $list.Items.Clear()
    $filter = $filterSelector.SelectedItem
    $searchText = (Get-SafeText -Value $searchBox.Text).Trim().ToLowerInvariant()

    foreach ($record in @(Read-Records)) {
        $recordType = Get-SafeText -Value $record.type -Fallback "idea"
        $recordText = Get-SafeText -Value $record.text -Fallback "(sin texto)"
        $recordStatus = Get-SafeText -Value $record.status -Fallback $(if ($recordType -eq "tarea") { "pendiente" } else { "activo" })
        $recordId = Get-SafeText -Value $record.id -Fallback "sin-id"
        $visible = $filter -eq "todos" -or
            ($filter -eq "ideas" -and $recordType -eq "idea") -or
            ($filter -eq "tareas" -and $recordType -eq "tarea") -or
            ($filter -eq "recuerdos" -and $recordType -eq "recuerdo")

        $matchesSearch = [string]::IsNullOrWhiteSpace($searchText) -or
            $recordText.ToLowerInvariant().Contains($searchText) -or
            $recordType.ToLowerInvariant().Contains($searchText) -or
            $recordStatus.ToLowerInvariant().Contains($searchText)

        if ($visible -and $matchesSearch) {
            $date = Get-SafeDateText -Value $record.created_at -Format "dd/MM/yyyy HH:mm"
            $item = New-Object System.Windows.Forms.ListViewItem($recordType)
            [void]$item.SubItems.Add($recordStatus)
            [void]$item.SubItems.Add($recordText)
            [void]$item.SubItems.Add($date)
            [void]$item.SubItems.Add($recordId)
            [void]$list.Items.Add($item)
        }
    }
}

function Refresh-Today {
    $records = @(Read-Records)
    $pendingTasks = @($records | Where-Object {
        (Get-SafeText -Value $_.type) -eq "tarea" -and
        (Get-SafeText -Value $_.status -Fallback "pendiente") -eq "pendiente"
    })
    $todayRecords = @($records | Where-Object { Test-IsToday -Value $_.created_at })
    $recentRecords = @($records | Sort-Object created_at -Descending | Select-Object -First 5)

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("Tareas pendientes: $($pendingTasks.Count)")
    $lines.Add("Registros cargados hoy: $($todayRecords.Count)")
    $lines.Add("")

    if ($pendingTasks.Count -gt 0) {
        $lines.Add("Pendiente ahora:")
        foreach ($task in @($pendingTasks | Select-Object -First 4)) {
            $lines.Add("- $(Get-SafeText -Value $task.text -Fallback '(sin texto)')")
        }
    }
    else {
        $lines.Add("No tenes tareas pendientes.")
    }

    $lines.Add("")
    $lines.Add("Ultimos movimientos:")
    if ($recentRecords.Count -eq 0) {
        $lines.Add("- Todavia no cargaste nada.")
    }
    else {
        foreach ($record in $recentRecords) {
            $date = Get-SafeDateText -Value $record.created_at -Format "dd/MM HH:mm"
            $type = Get-SafeText -Value $record.type -Fallback "idea"
            $text = Get-SafeText -Value $record.text -Fallback "(sin texto)"
            $lines.Add("- [$type] $date - $text")
        }
    }

    $todayText.Text = [string]::Join([Environment]::NewLine, $lines)
}

function Refresh-Screen {
    try {
        Refresh-List
        Refresh-Today
    }
    catch {
        $statusLabel.Text = "Error al refrescar: $($_.Exception.Message)"
    }
}

function Get-SelectedId {
    if ($list.SelectedItems.Count -eq 0) {
        throw "Selecciona un registro de la lista."
    }

    return $list.SelectedItems[0].SubItems[4].Text
}

$saveButton.Add_Click({
    try {
        Add-Record -Type $typeSelector.SelectedItem -Text $input.Text
        $input.Clear()
        Refresh-Screen
        $statusLabel.Text = "Guardado correctamente."
        $input.Focus()
    }
    catch {
        $statusLabel.Text = $_.Exception.Message
    }
})

$quickButton.Add_Click({
    try {
        $capture = Get-QuickCapture -Text $input.Text
        Add-Record -Type $capture.type -Text $capture.text
        $typeSelector.SelectedItem = $capture.type
        $input.Clear()
        Refresh-Screen
        $statusLabel.Text = "Captura rapida guardada como '$($capture.type)'."
        $input.Focus()
    }
    catch {
        $statusLabel.Text = $_.Exception.Message
    }
})

$completeButton.Add_Click({
    try {
        Complete-Task -Id (Get-SelectedId)
        Refresh-Screen
        $statusLabel.Text = "Tarea completada."
    }
    catch {
        $statusLabel.Text = $_.Exception.Message
    }
})

$editButton.Add_Click({
    try {
        $id = Get-SelectedId
        $records = @(Read-Records)
        $record = $records | Where-Object { $_.id -eq $id } | Select-Object -First 1
        if (-not $record) {
            throw "No encontre el registro seleccionado."
        }

        $newText = [Microsoft.VisualBasic.Interaction]::InputBox(
            "Edita el texto del registro:",
            "Editar en Jarvis",
            $record.text
        )

        if (-not [string]::IsNullOrWhiteSpace($newText)) {
            Update-RecordText -Id $id -Text $newText
            Refresh-Screen
            $statusLabel.Text = "Registro editado."
        }
    }
    catch {
        $statusLabel.Text = $_.Exception.Message
    }
})

$deleteButton.Add_Click({
    try {
        $id = Get-SelectedId
        $answer = [System.Windows.Forms.MessageBox]::Show(
            "Queres borrar el registro seleccionado?",
            "Confirmar borrado",
            "YesNo",
            "Question"
        )
        if ($answer -eq "Yes") {
            Remove-Record -Id $id
            Refresh-Screen
            $statusLabel.Text = "Registro eliminado."
        }
    }
    catch {
        $statusLabel.Text = $_.Exception.Message
    }
})

$backupButton.Add_Click({
    try {
        $backupPath = New-DataBackup -Reason "manual"
        $statusLabel.Text = "Backup creado: $(Split-Path -Path $backupPath -Leaf)"
    }
    catch {
        $statusLabel.Text = "No pude crear backup: $($_.Exception.Message)"
    }
})

$filterSelector.Add_SelectedIndexChanged({ Refresh-Screen })
$searchBox.Add_TextChanged({ Refresh-Screen })
$refreshButton.Add_Click({ Refresh-Screen })
$form.Add_Shown({ Refresh-Screen; $input.Focus() })

if ($SmokeTest) {
    Refresh-Screen
    [void](Get-QuickCapture -Text "tengo que estudiar matematica")
    [void](Get-QuickCapture -Text "recorda que tengo dentista")
    [void](Get-QuickCapture -Text "idea armar control de gastos")
    Write-Host "Jarvis GUI OK. Registros visibles: $($list.Items.Count)"
}
else {
    [void]$form.ShowDialog()
}
