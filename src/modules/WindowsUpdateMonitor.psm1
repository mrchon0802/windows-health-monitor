Set-StrictMode -Version Latest

function Get-WindowsUpdateHistoryRaw {
    [CmdletBinding()]
    param([ValidateRange(1,500)][int]$MaxEntries = 20)

    try {
        $session = New-Object -ComObject Microsoft.Update.Session -ErrorAction Stop
        $searcher = $session.CreateUpdateSearcher()
        $count = [int]$searcher.GetTotalHistoryCount()
        if ($count -le 0) { return @() }

        $take = [Math]::Min($count, $MaxEntries)
        @($searcher.QueryHistory(0, $take))
    }
    catch {
        throw "Unable to read Windows Update history: $($_.Exception.Message)"
    }
}

function Get-WindowsUpdateHistory {
    [CmdletBinding()]
    param([ValidateRange(1,500)][int]$MaxEntries = 20)

    $resultNames = @{
        0 = 'NotStarted'
        1 = 'InProgress'
        2 = 'Succeeded'
        3 = 'SucceededWithErrors'
        4 = 'Failed'
        5 = 'Aborted'
    }

    $rawHistory = @(Get-WindowsUpdateHistoryRaw -MaxEntries $MaxEntries)
    foreach ($item in $rawHistory) {
        # IUpdateHistoryEntry exposes ResultCode. OperationResultCode is
        # accepted as a compatibility fallback for older/custom test objects.
        $resultCodeProperty = $item.PSObject.Properties['ResultCode']
        if ($null -ne $resultCodeProperty) {
            $code = [int]$resultCodeProperty.Value
        }
        else {
            $legacyProperty = $item.PSObject.Properties['OperationResultCode']
            if ($null -eq $legacyProperty) {
                throw "Windows Update history entry does not expose ResultCode."
            }
            $code = [int]$legacyProperty.Value
        }

        $result = if ($resultNames.ContainsKey($code)) { $resultNames[$code] } else { 'Unknown' }
        [pscustomobject]@{
            Date       = $item.Date
            Title      = [string]$item.Title
            Result     = $result
            ResultCode = $code
            HResult    = if ($null -ne $item.HResult) { '0x{0:X8}' -f ([uint32]([long]$item.HResult -band 4294967295)) } else { $null }
            UpdateId   = if ($null -ne $item.UpdateIdentity) { [string]$item.UpdateIdentity.UpdateID } else { $null }
        }
    }
}

function Get-PendingRebootIndicators {
    [CmdletBinding()]
    param()

    $indicators = [System.Collections.Generic.List[string]]::new()
    $registryChecks = @(
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'; Name = 'CBS Reboot Pending' },
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'; Name = 'Windows Update Reboot Required' }
    )

    foreach ($check in $registryChecks) {
        if (Test-Path -LiteralPath $check.Path) {
            $indicators.Add($check.Name)
        }
    }

    $sessionManagerPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
    try {
        $sessionManager = Get-ItemProperty -LiteralPath $sessionManagerPath -Name PendingFileRenameOperations -ErrorAction Stop
        if ($sessionManager.PendingFileRenameOperations) {
            $indicators.Add('Pending File Rename Operations')
        }
    }
    catch {
        # The value is optional and commonly absent; absence is not an error.
    }

    @($indicators)
}

function Get-PendingRebootStatus {
    [CmdletBinding()]
    param()

    $indicators = @(Get-PendingRebootIndicators)
    [pscustomobject]@{
        IsPending  = ($indicators.Count -gt 0)
        Status     = if ($indicators.Count -gt 0) { 'Warning' } else { 'Healthy' }
        Indicators = $indicators
        CheckedAt  = Get-Date
    }
}

function Invoke-WindowsUpdateMonitoring {
    [CmdletBinding()]
    param([ValidateRange(1,500)][int]$HistoryLimit = 20)

    $history = @()
    $historyStatus = 'OK'
    $historyError = $null
    try {
        $history = @(Get-WindowsUpdateHistory -MaxEntries $HistoryLimit)
    }
    catch {
        $historyStatus = 'Unknown'
        $historyError = $_.Exception.Message
    }

    $failedUpdates = @($history | Where-Object Result -in @('Failed','Aborted'))
    $pendingReboot = Get-PendingRebootStatus

    $overallStatus = if ($historyStatus -eq 'Unknown') {
        'Unknown'
    }
    elseif ($failedUpdates.Count -gt 0 -or $pendingReboot.IsPending) {
        'Warning'
    }
    else {
        'Healthy'
    }

    [pscustomobject]@{
        CollectedAt    = Get-Date
        History        = $history
        HistoryStatus  = $historyStatus
        HistoryError   = $historyError
        FailedUpdates  = $failedUpdates
        PendingReboot  = $pendingReboot
        OverallStatus  = $overallStatus
    }
}

Export-ModuleMember -Function Get-WindowsUpdateHistory, Get-PendingRebootStatus, Invoke-WindowsUpdateMonitoring
