BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../src/modules/WindowsUpdateMonitor.psm1') -Force
}

Describe 'WindowsUpdateMonitor module' {
    It 'normalizes Windows Update result codes from the Windows API ResultCode property' {
        Mock Get-WindowsUpdateHistoryRaw {
            @(
                [pscustomobject]@{ Date = [datetime]'2026-11-18'; Title = 'Cumulative Update'; ResultCode = 2; HResult = 0; UpdateIdentity = $null }
                [pscustomobject]@{ Date = [datetime]'2026-11-17'; Title = 'Security Update'; ResultCode = 4; HResult = -2145124329; UpdateIdentity = $null }
            )
        } -ModuleName WindowsUpdateMonitor

        $result = @(Get-WindowsUpdateHistory -MaxEntries 10)
        $result.Count | Should -Be 2
        $result[0].Result | Should -Be 'Succeeded'
        $result[1].Result | Should -Be 'Failed'
    }

    It 'supports legacy objects exposing OperationResultCode' {
        Mock Get-WindowsUpdateHistoryRaw {
            @([pscustomobject]@{ Date = [datetime]'2026-11-18'; Title = 'Legacy Test'; OperationResultCode = 2; HResult = 0; UpdateIdentity = $null })
        } -ModuleName WindowsUpdateMonitor

        $result = @(Get-WindowsUpdateHistory)
        $result[0].Result | Should -Be 'Succeeded'
    }

    It 'reports no pending reboot when no indicators exist' {
        Mock Get-PendingRebootIndicators { @() } -ModuleName WindowsUpdateMonitor
        $result = Get-PendingRebootStatus
        $result.IsPending | Should -BeFalse
        $result.Status | Should -Be 'Healthy'
    }

    It 'reports pending reboot when indicators exist' {
        Mock Get-PendingRebootIndicators { @('CBS Reboot Pending') } -ModuleName WindowsUpdateMonitor
        $result = Get-PendingRebootStatus
        $result.IsPending | Should -BeTrue
        $result.Indicators | Should -Contain 'CBS Reboot Pending'
    }

    It 'returns Healthy when updates succeeded and no reboot is pending' {
        Mock Get-WindowsUpdateHistory { @([pscustomobject]@{ Title='Update'; Result='Succeeded' }) } -ModuleName WindowsUpdateMonitor
        Mock Get-PendingRebootStatus { [pscustomobject]@{ IsPending=$false; Status='Healthy'; Indicators=@() } } -ModuleName WindowsUpdateMonitor
        (Invoke-WindowsUpdateMonitoring).OverallStatus | Should -Be 'Healthy'
    }

    It 'returns Warning when failed updates are present' {
        Mock Get-WindowsUpdateHistory { @([pscustomobject]@{ Title='Update'; Result='Failed' }) } -ModuleName WindowsUpdateMonitor
        Mock Get-PendingRebootStatus { [pscustomobject]@{ IsPending=$false; Status='Healthy'; Indicators=@() } } -ModuleName WindowsUpdateMonitor
        $result = Invoke-WindowsUpdateMonitoring
        $result.OverallStatus | Should -Be 'Warning'
        $result.FailedUpdates.Count | Should -Be 1
    }

    It 'returns Warning when a reboot is pending' {
        Mock Get-WindowsUpdateHistory { @() } -ModuleName WindowsUpdateMonitor
        Mock Get-PendingRebootStatus { [pscustomobject]@{ IsPending=$true; Status='Warning'; Indicators=@('Windows Update Reboot Required') } } -ModuleName WindowsUpdateMonitor
        (Invoke-WindowsUpdateMonitoring).OverallStatus | Should -Be 'Warning'
    }

    It 'returns Unknown when update history cannot be read' {
        Mock Get-WindowsUpdateHistory { throw 'COM unavailable' } -ModuleName WindowsUpdateMonitor
        Mock Get-PendingRebootStatus { [pscustomobject]@{ IsPending=$false; Status='Healthy'; Indicators=@() } } -ModuleName WindowsUpdateMonitor
        $result = Invoke-WindowsUpdateMonitoring
        $result.OverallStatus | Should -Be 'Unknown'
        $result.HistoryError | Should -Match 'COM unavailable'
    }
}
