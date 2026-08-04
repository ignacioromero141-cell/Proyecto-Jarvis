# Reglas principales del modulo Finanzas.
# Aca validamos movimientos y evitamos que la pantalla conozca detalles de datos.

. (Join-Path $PSScriptRoot "finance-storage.ps1")

function Get-FinanceSafeText {
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

function Get-FinanceLocalDeviceId {
    if (Get-Command Get-JarvisDeviceId -ErrorAction SilentlyContinue) {
        return Get-JarvisDeviceId
    }

    return "notebook-local"
}

function Set-FinanceMovementProperty {
    param(
        $Movement,
        [string]$Name,
        $Value
    )

    if ($Movement.PSObject.Properties.Name -contains $Name) {
        $Movement.$Name = $Value
    }
    else {
        $Movement | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Get-FinanceVisibleMovements {
    return @(Read-FinanceMovements | Where-Object {
        [string]::IsNullOrWhiteSpace((Get-FinanceSafeText -Value $_.deleted_at))
    })
}

function Update-FinanceMovementSyncMetadata {
    param($Movement)

    $revision = 0
    try {
        $revision = [int](Get-FinanceSafeText -Value $Movement.revision -Fallback "0")
    }
    catch {
        $revision = 0
    }

    Set-FinanceMovementProperty -Movement $Movement -Name "device_id" -Value (Get-FinanceSafeText -Value $Movement.device_id -Fallback (Get-FinanceLocalDeviceId))
    Set-FinanceMovementProperty -Movement $Movement -Name "revision" -Value ($revision + 1)
    Set-FinanceMovementProperty -Movement $Movement -Name "synced_at" -Value $null
}

function Get-FinanceCategoryById {
    param([string]$CategoryId)

    return Read-FinanceCategories |
        Where-Object { $_.id -eq $CategoryId -and $_.enabled -ne $false } |
        Select-Object -First 1
}

function Get-FinancePriorityById {
    param([string]$PriorityId)

    return Read-FinancePriorities |
        Where-Object { $_.id -eq $PriorityId } |
        Select-Object -First 1
}

function Add-FinanceMovement {
    param(
        [string]$Kind,
        [string]$CategoryId,
        [string]$Priority,
        [decimal]$Amount,
        [string]$Date,
        [string]$Note = "",
        [string]$PaymentMethod = ""
    )

    if (@("income", "expense", "saving") -notcontains $Kind) {
        throw "Tipo invalido. Usa income, expense o saving."
    }
    if ($Amount -le 0) {
        throw "El monto debe ser mayor que cero."
    }

    $category = Get-FinanceCategoryById -CategoryId $CategoryId
    if (-not $category) {
        throw "Categoria invalida: $CategoryId."
    }

    $priorityRecord = Get-FinancePriorityById -PriorityId $Priority
    if (-not $priorityRecord) {
        throw "Prioridad invalida: $Priority."
    }

    try {
        $parsedDate = ([datetime]::Parse($Date)).ToString("yyyy-MM-dd")
    }
    catch {
        throw "Fecha invalida. Usa formato YYYY-MM-DD."
    }

    $settings = Read-FinanceSettings
    $currency = Get-FinanceSafeText -Value $settings.currency -Fallback "ARS"
    $payment = Get-FinanceSafeText -Value $PaymentMethod -Fallback (Get-FinanceSafeText -Value $settings.default_payment_method -Fallback "cash")
    $now = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")

    $movements = @(Read-FinanceMovements)
    $movement = [pscustomobject]@{
        id = [guid]::NewGuid().ToString("N")
        kind = $Kind
        category_id = $CategoryId
        priority = $Priority
        amount = [decimal]$Amount
        currency = $currency
        date = $parsedDate
        note = $Note.Trim()
        payment_method = $payment
        source = "manual"
        device_id = Get-FinanceLocalDeviceId
        revision = 1
        deleted_at = $null
        synced_at = $null
        created_at = $now
        updated_at = $now
    }

    $movements += $movement
    Write-FinanceMovements -Movements $movements -BackupReason "movement-add"
    return $movement
}

function Remove-FinanceMovement {
    param([string]$Id)

    $movements = @(Read-FinanceMovements)
    $movement = $movements | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if (-not $movement) {
        return
    }

    $now = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    Set-FinanceMovementProperty -Movement $movement -Name "deleted_at" -Value $now
    Set-FinanceMovementProperty -Movement $movement -Name "updated_at" -Value $now
    Update-FinanceMovementSyncMetadata -Movement $movement
    Write-FinanceMovements -Movements $movements -BackupReason "movement-delete"
}

function Get-FinanceTargets {
    $settings = Read-FinanceSettings

    $targets = $settings.monthly_targets
    if ($null -eq $targets) {
        $targets = [pscustomobject]@{
            saving = 30
            necessary = 20
            optional = 40
            personal_investment = 10
        }
    }

    return [pscustomobject]@{
        saving = [decimal]$targets.saving
        necessary = [decimal]$targets.necessary
        optional = [decimal]$targets.optional
        personal_investment = [decimal]$targets.personal_investment
    }
}

function Set-FinanceTargets {
    param(
        [decimal]$Saving,
        [decimal]$Necessary,
        [decimal]$Optional,
        [decimal]$PersonalInvestment
    )

    $total = $Saving + $Necessary + $Optional + $PersonalInvestment
    if ($total -ne 100) {
        throw "Las metas deben sumar 100%. Ahora suman $total%."
    }

    $settings = Read-FinanceSettings
    $settings | Add-Member -NotePropertyName "monthly_targets" -NotePropertyValue ([pscustomobject]@{
        saving = $Saving
        necessary = $Necessary
        optional = $Optional
        personal_investment = $PersonalInvestment
    }) -Force
    $settings | Add-Member -NotePropertyName "updated_at" -NotePropertyValue ((Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")) -Force

    Write-FinanceSettings -Settings $settings -BackupReason "targets-update"
    return Get-FinanceTargets
}
