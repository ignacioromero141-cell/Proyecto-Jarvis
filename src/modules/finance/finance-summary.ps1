# Calculos del modulo Finanzas.
# Separar los calculos permite probarlos sin depender de la interfaz.

. (Join-Path $PSScriptRoot "finance-core.ps1")

function Get-FinanceMonthKey {
    param([datetime]$Date = (Get-Date))

    return $Date.ToString("yyyy-MM")
}

function Get-FinancePercentOfIncome {
    param(
        [decimal]$Value,
        [decimal]$Income
    )

    if ($Income -le 0) {
        return [decimal]0
    }

    return [math]::Round(($Value / $Income) * 100, 1)
}

function Get-FinanceTargetStatus {
    param(
        [string]$Group,
        [decimal]$Real,
        [decimal]$Target
    )

    $difference = $Real - $Target

    if ($Group -eq "saving") {
        if ($Real -ge $Target) { return "cumplido" }
        if ($Real -ge ($Target - 5)) { return "cerca" }
        return "bajo"
    }

    if ($Real -le $Target) { return "cumplido" }
    if ($Real -le ($Target + 5)) { return "cerca" }
    return "excedido"
}

function Get-FinanceMonthTotals {
    param([array]$Movements)

    $income = [decimal]0
    $expense = [decimal]0
    $saving = [decimal]0
    $necessary = [decimal]0
    $optional = [decimal]0
    $personalInvestment = [decimal]0

    foreach ($movement in $Movements) {
        $amount = [decimal]$movement.amount
        switch ($movement.kind) {
            "income" { $income += $amount }
            "expense" { $expense += $amount }
            "saving" { $saving += $amount }
        }

        if ($movement.kind -eq "expense") {
            switch ($movement.priority) {
                "necessary" { $necessary += $amount }
                "optional" { $optional += $amount }
                "personal_investment" { $personalInvestment += $amount }
            }
        }
    }

    return [pscustomobject]@{
        income = $income
        expense = $expense
        saving = $saving
        balance = $income - $expense - $saving
        necessary = $necessary
        optional = $optional
        personal_investment = $personalInvestment
    }
}

function Get-FinanceMonthlyAnalysis {
    param(
        $Totals,
        $Targets
    )

    $groups = @(
        @{ id = "saving"; label = "Ahorro e inversiones"; total = $Totals.saving; target = $Targets.saving },
        @{ id = "necessary"; label = "Gastos necesarios"; total = $Totals.necessary; target = $Targets.necessary },
        @{ id = "optional"; label = "Salidas o prescindibles"; total = $Totals.optional; target = $Targets.optional },
        @{ id = "personal_investment"; label = "Inversion personal"; total = $Totals.personal_investment; target = $Targets.personal_investment }
    )

    foreach ($group in $groups) {
        $real = Get-FinancePercentOfIncome -Value ([decimal]$group.total) -Income ([decimal]$Totals.income)
        [pscustomobject]@{
            id = $group.id
            label = $group.label
            total = [decimal]$group.total
            percent = $real
            target = [decimal]$group.target
            status = Get-FinanceTargetStatus -Group $group.id -Real $real -Target ([decimal]$group.target)
        }
    }
}

function Get-FinanceMonthSeries {
    $allMovements = @(Get-FinanceVisibleMovements)
    $months = @($allMovements |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_.date) } |
        ForEach-Object { $_.date.Substring(0, 7) } |
        Sort-Object -Unique)

    foreach ($month in $months) {
        $monthMovements = @($allMovements | Where-Object {
            (Get-FinanceSafeText -Value $_.date).StartsWith($month)
        })
        $totals = Get-FinanceMonthTotals -Movements $monthMovements

        [pscustomobject]@{
            month = $month
            income_total = $totals.income
            expense_total = $totals.expense
            saving_total = $totals.saving
            balance = $totals.balance
        }
    }
}

function Get-FinancePreviousMonthComparison {
    param([string]$Month)

    try {
        $currentDate = [datetime]::Parse("$Month-01")
        $previousMonth = $currentDate.AddMonths(-1).ToString("yyyy-MM")
    }
    catch {
        return [pscustomobject]@{
            previous_month = $null
            has_previous = $false
            message = "Mes invalido."
        }
    }

    $currentMovements = @(Get-FinanceVisibleMovements | Where-Object {
        (Get-FinanceSafeText -Value $_.date).StartsWith($Month)
    })
    $previousMovements = @(Get-FinanceVisibleMovements | Where-Object {
        (Get-FinanceSafeText -Value $_.date).StartsWith($previousMonth)
    })

    if ($previousMovements.Count -eq 0) {
        return [pscustomobject]@{
            previous_month = $previousMonth
            has_previous = $false
            message = "No hay datos del mes anterior."
        }
    }

    $current = Get-FinanceMonthTotals -Movements $currentMovements
    $previous = Get-FinanceMonthTotals -Movements $previousMovements

    function Get-Change {
        param([decimal]$Current, [decimal]$Previous)
        $diff = $Current - $Previous
        $percent = if ($Previous -eq 0) { $null } else { [math]::Round(($diff / $Previous) * 100, 1) }
        return [pscustomobject]@{ current = $Current; previous = $Previous; difference = $diff; percent = $percent }
    }

    return [pscustomobject]@{
        previous_month = $previousMonth
        has_previous = $true
        income = Get-Change -Current $current.income -Previous $previous.income
        expense = Get-Change -Current $current.expense -Previous $previous.expense
        saving = Get-Change -Current $current.saving -Previous $previous.saving
        balance = Get-Change -Current $current.balance -Previous $previous.balance
    }
}

function Get-FinanceMonthlySummary {
    param([string]$Month = (Get-FinanceMonthKey))

    $movements = @(Get-FinanceVisibleMovements | Where-Object {
        (Get-FinanceSafeText -Value $_.date).StartsWith($Month)
    })
    $categories = @(Read-FinanceCategories)
    $priorities = @(Read-FinancePriorities)

    $totals = Get-FinanceMonthTotals -Movements $movements
    $targets = Get-FinanceTargets

    $byCategory = foreach ($category in $categories) {
        $categoryMovements = @($movements | Where-Object { $_.category_id -eq $category.id })
        $total = [decimal]0
        foreach ($movement in $categoryMovements) {
            $total += [decimal]$movement.amount
        }

        [pscustomobject]@{
            id = $category.id
            label = $category.label
            kind = $category.kind
            total = $total
            count = $categoryMovements.Count
        }
    }

    $byPriority = foreach ($priority in $priorities) {
        $priorityMovements = @($movements | Where-Object { $_.priority -eq $priority.id })
        $total = [decimal]0
        foreach ($movement in $priorityMovements) {
            $total += [decimal]$movement.amount
        }

        [pscustomobject]@{
            id = $priority.id
            label = $priority.label
            total = $total
            count = $priorityMovements.Count
        }
    }

    return [pscustomobject]@{
        month = $Month
        income_total = $totals.income
        expense_total = $totals.expense
        saving_total = $totals.saving
        balance = $totals.balance
        movement_count = $movements.Count
        by_category = @($byCategory)
        by_priority = @($byPriority)
        analysis = @(Get-FinanceMonthlyAnalysis -Totals $totals -Targets $targets)
        targets = $targets
        month_series = @(Get-FinanceMonthSeries)
        previous_comparison = (Get-FinancePreviousMonthComparison -Month $Month)
    }
}
