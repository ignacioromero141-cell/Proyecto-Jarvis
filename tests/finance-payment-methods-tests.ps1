param()

$ErrorActionPreference = "Stop"
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. (Join-Path $ProjectRoot "src\web\server.ps1")

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

$root = Join-Path $env:TEMP "jarvis-finance-methods-test-$([guid]::NewGuid().ToString("N"))"
New-Item -ItemType Directory -Path $root | Out-Null
Initialize-JarvisStorage -ProjectRoot $root
Initialize-FinanceStorage -ProjectRoot $root
Initialize-JarvisSyncStorage

@(
    [pscustomobject]@{ id = "income"; label = "Ingreso"; kind = "income"; enabled = $true; sort_order = 10 },
    [pscustomobject]@{ id = "food"; label = "Comida"; kind = "expense"; enabled = $true; sort_order = 20 }
) | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $root "data\finance\categories.json") -Encoding UTF8

@(
    [pscustomobject]@{ id = "necessary"; label = "Necesario"; sort_order = 10 }
) | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $root "data\finance\priorities.json") -Encoding UTF8

$methods = @(Read-FinancePaymentMethods)
Assert-True ($methods.Count -ge 5) "No se crearon metodos iniciales."
Assert-True (@($methods | Where-Object { $_.id -eq "cash" -and $_.label -eq "Efectivo" }).Count -eq 1) "Falta metodo Efectivo."

$custom = Add-FinancePaymentMethod -Label "Mercado Pago"
Assert-True (-not [string]::IsNullOrWhiteSpace($custom.id)) "No se creo metodo personalizado."

$movement = Add-FinanceMovement -Kind "expense" -CategoryId "food" -Priority "necessary" -Amount 1000 -Date "2026-08-10" -Note "test" -PaymentMethodId $custom.id
Assert-True ($movement.payment_method_id -eq $custom.id -and $movement.payment_method -eq "Mercado Pago") "El movimiento no guardo metodo configurable."

$updated = Update-FinanceMovement -Id $movement.id -Kind "income" -CategoryId "income" -Priority "necessary" -Amount 2000 -Date "2026-08-10" -Note "cobro test" -PaymentMethodId "transfer"
Assert-True ($updated.payment_method_id -eq "transfer" -and $updated.payment_method -eq "Transferencia") "La edicion no actualizo metodo."

Update-FinancePaymentMethod -Id $custom.id -Label "MP" -Enabled $false | Out-Null
$hidden = Get-FinancePaymentMethodById -PaymentMethodId $custom.id
Assert-True ($hidden.enabled -eq $false) "No se pudo ocultar metodo personalizado."

Remove-FinancePaymentMethod -Id $custom.id
$deletedMethod = Read-FinancePaymentMethods | Where-Object { $_.id -eq $custom.id } | Select-Object -First 1
Assert-True (-not [string]::IsNullOrWhiteSpace($deletedMethod.deleted_at)) "No se marco como eliminado el metodo personalizado."

$storedMovement = Read-FinanceMovements | Where-Object { $_.id -eq $movement.id } | Select-Object -First 1
Assert-True ($storedMovement.payment_method -eq "Transferencia") "El movimiento historico perdio su metodo visible."

$changes = @(Get-JarvisSyncChangesSince)
Assert-True (@($changes | Where-Object { $_.entity -eq "finance_payment_methods" }).Count -gt 0) "Los metodos no entraron al historial de sync."

Write-Host "Jarvis finance payment method tests OK"
