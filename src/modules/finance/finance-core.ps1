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

function Get-FinanceVisiblePaymentMethods {
    return @(Read-FinancePaymentMethods | Where-Object {
        [string]::IsNullOrWhiteSpace((Get-FinanceSafeText -Value $_.deleted_at))
    } | Sort-Object sort_order, label)
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

function Get-FinancePaymentMethodById {
    param([string]$PaymentMethodId)

    return Read-FinancePaymentMethods |
        Where-Object { $_.id -eq $PaymentMethodId -and [string]::IsNullOrWhiteSpace((Get-FinanceSafeText -Value $_.deleted_at)) } |
        Select-Object -First 1
}

function Get-FinancePaymentMethodLabel {
    param(
        [string]$PaymentMethodId,
        [string]$LegacyPaymentMethod = ""
    )

    $method = Get-FinancePaymentMethodById -PaymentMethodId $PaymentMethodId
    if ($method) {
        return Get-FinanceSafeText -Value $method.label -Fallback $PaymentMethodId
    }

    return Get-FinanceSafeText -Value $LegacyPaymentMethod -Fallback "Efectivo"
}

function Add-FinancePaymentMethod {
    param([string]$Label)

    $safeLabel = Get-FinanceSafeText -Value $Label
    if ([string]::IsNullOrWhiteSpace($safeLabel)) {
        throw "Escribi un nombre para el metodo."
    }

    $now = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    $methods = @(Read-FinancePaymentMethods)
    $method = [pscustomobject]@{
        id = "method-$([guid]::NewGuid().ToString("N"))"
        label = $safeLabel.Trim()
        enabled = $true
        built_in = $false
        sort_order = 100 + $methods.Count
        deleted_at = $null
        created_at = $now
        updated_at = $now
    }

    $methods += $method
    Write-FinancePaymentMethods -PaymentMethods $methods -BackupReason "payment-method-add"
    if (Get-Command Add-JarvisSyncChange -ErrorAction SilentlyContinue) {
        Add-JarvisSyncChange -Entity "finance_payment_methods" -EntityId $method.id -Operation "create" -Value $method | Out-Null
    }
    return $method
}

function Update-FinancePaymentMethod {
    param(
        [string]$Id,
        [string]$Label,
        [bool]$Enabled
    )

    $methods = @(Read-FinancePaymentMethods)
    $method = $methods | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if (-not $method) {
        throw "No encontre ese metodo."
    }
    if ($method.built_in -eq $true) {
        throw "Los metodos iniciales no se editan desde esta pantalla."
    }

    $safeLabel = Get-FinanceSafeText -Value $Label -Fallback (Get-FinanceSafeText -Value $method.label)
    if ([string]::IsNullOrWhiteSpace($safeLabel)) {
        throw "El nombre del metodo no puede estar vacio."
    }

    $method.label = $safeLabel.Trim()
    $method.enabled = $Enabled
    $method.updated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    Write-FinancePaymentMethods -PaymentMethods $methods -BackupReason "payment-method-update"
    if (Get-Command Add-JarvisSyncChange -ErrorAction SilentlyContinue) {
        Add-JarvisSyncChange -Entity "finance_payment_methods" -EntityId $method.id -Operation "update" -Value $method | Out-Null
    }
    return $method
}

function Remove-FinancePaymentMethod {
    param([string]$Id)

    $methods = @(Read-FinancePaymentMethods)
    $method = $methods | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if (-not $method) {
        return
    }
    if ($method.built_in -eq $true) {
        throw "Los metodos iniciales no se eliminan."
    }

    $now = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    $method.enabled = $false
    $method.deleted_at = $now
    $method.updated_at = $now
    Write-FinancePaymentMethods -PaymentMethods $methods -BackupReason "payment-method-delete"
    if (Get-Command Add-JarvisSyncChange -ErrorAction SilentlyContinue) {
        Add-JarvisSyncChange -Entity "finance_payment_methods" -EntityId $method.id -Operation "delete" -Value $method | Out-Null
    }
}

function Add-FinanceMovement {
    param(
        [string]$Kind,
        [string]$CategoryId,
        [string]$Priority,
        [decimal]$Amount,
        [string]$Date,
        [string]$Note = "",
        [string]$PaymentMethodId = "",
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
    $safePaymentMethodId = Get-FinanceSafeText -Value $PaymentMethodId -Fallback (Get-FinanceSafeText -Value $settings.default_payment_method -Fallback "cash")
    if (-not (Get-FinancePaymentMethodById -PaymentMethodId $safePaymentMethodId)) {
        $safePaymentMethodId = ""
    }
    $payment = Get-FinancePaymentMethodLabel -PaymentMethodId $safePaymentMethodId -LegacyPaymentMethod $PaymentMethod
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
        payment_method_id = $safePaymentMethodId
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
    if (Get-Command Add-JarvisSyncChange -ErrorAction SilentlyContinue) {
        Add-JarvisSyncChange -Entity "finance_movements" -EntityId $movement.id -Operation "create" -Value $movement | Out-Null
    }
    return $movement
}

function Update-FinanceMovement {
    param(
        [string]$Id,
        [string]$Kind,
        [string]$CategoryId,
        [string]$Priority,
        [decimal]$Amount,
        [string]$Date,
        [string]$Note = "",
        [string]$PaymentMethodId = "",
        [string]$PaymentMethod = ""
    )

    $movements = @(Read-FinanceMovements)
    $movement = $movements | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if (-not $movement) {
        throw "No encontre ese movimiento."
    }
    if (@("income", "expense", "saving") -notcontains $Kind) {
        throw "Tipo invalido. Usa income, expense o saving."
    }
    if ($Amount -le 0) {
        throw "El monto debe ser mayor que cero."
    }
    if (-not (Get-FinanceCategoryById -CategoryId $CategoryId)) {
        throw "Categoria invalida: $CategoryId."
    }
    if (-not (Get-FinancePriorityById -PriorityId $Priority)) {
        throw "Prioridad invalida: $Priority."
    }

    try {
        $parsedDate = ([datetime]::Parse($Date)).ToString("yyyy-MM-dd")
    }
    catch {
        throw "Fecha invalida. Usa formato YYYY-MM-DD."
    }

    $safePaymentMethodId = Get-FinanceSafeText -Value $PaymentMethodId
    if (-not (Get-FinancePaymentMethodById -PaymentMethodId $safePaymentMethodId)) {
        $safePaymentMethodId = ""
    }
    $payment = Get-FinancePaymentMethodLabel -PaymentMethodId $safePaymentMethodId -LegacyPaymentMethod $PaymentMethod

    Set-FinanceMovementProperty -Movement $movement -Name "kind" -Value $Kind
    Set-FinanceMovementProperty -Movement $movement -Name "category_id" -Value $CategoryId
    Set-FinanceMovementProperty -Movement $movement -Name "priority" -Value $Priority
    Set-FinanceMovementProperty -Movement $movement -Name "amount" -Value ([decimal]$Amount)
    Set-FinanceMovementProperty -Movement $movement -Name "date" -Value $parsedDate
    Set-FinanceMovementProperty -Movement $movement -Name "note" -Value $Note.Trim()
    Set-FinanceMovementProperty -Movement $movement -Name "payment_method_id" -Value $safePaymentMethodId
    Set-FinanceMovementProperty -Movement $movement -Name "payment_method" -Value $payment
    Set-FinanceMovementProperty -Movement $movement -Name "updated_at" -Value ((Get-Date).ToString("yyyy-MM-ddTHH:mm:ss"))
    Update-FinanceMovementSyncMetadata -Movement $movement

    Write-FinanceMovements -Movements $movements -BackupReason "movement-update"
    if (Get-Command Add-JarvisSyncChange -ErrorAction SilentlyContinue) {
        Add-JarvisSyncChange -Entity "finance_movements" -EntityId $movement.id -Operation "update" -Value $movement | Out-Null
    }
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
    if (Get-Command Add-JarvisSyncChange -ErrorAction SilentlyContinue) {
        Add-JarvisSyncChange -Entity "finance_movements" -EntityId $movement.id -Operation "delete" -Value $movement | Out-Null
    }
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
    if (Get-Command Add-JarvisSyncChange -ErrorAction SilentlyContinue) {
        $settings | Add-Member -NotePropertyName "id" -NotePropertyValue "main" -Force
        Add-JarvisSyncChange -Entity "finance_settings" -EntityId "main" -Operation "update" -Value $settings | Out-Null
    }
    return Get-FinanceTargets
}
