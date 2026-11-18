BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../src/modules/EventLogAnalyzer.psm1') -Force
}

Describe 'EventLogAnalyzer module' {
    It 'maps numeric Windows event levels to readable names' {
        InModuleScope EventLogAnalyzer {
            (Get-EventLevelName -Level 1) | Should -Be 'Critical'
            (Get-EventLevelName -Level 2) | Should -Be 'Error'
            (Get-EventLevelName -Level 3) | Should -Be 'Warning'
        }
    }

    It 'normalizes Windows event records' {
        Mock Get-WinEvent {
            @([pscustomobject]@{
                TimeCreated = [datetime]'2026-11-18T10:00:00'
                Level = 2
                LevelDisplayName = 'Error'
                Id = 1001
                ProviderName = 'TestProvider'
                MachineName = 'TEST-PC'
                Message = 'Test event message'
            })
        } -ModuleName EventLogAnalyzer

        $result = @(Get-EventLogRecords -LogName System -StartTime (Get-Date).AddDays(-1))
        $result.Count | Should -Be 1
        $result[0].Level | Should -Be 'Error'
        $result[0].Id | Should -Be 1001
        $result[0].Source | Should -Be 'TestProvider'
    }

    It 'returns an empty collection when no matching events exist' {
        Mock Get-WinEvent { throw 'No events were found that match the specified selection criteria.' } -ModuleName EventLogAnalyzer
        $result = @(Get-EventLogRecords -LogName System -StartTime (Get-Date).AddDays(-1))
        $result.Count | Should -Be 0
    }

    It 'throws a useful error when an event log cannot be read' {
        Mock Get-WinEvent { throw 'Access is denied.' } -ModuleName EventLogAnalyzer
        { Get-EventLogRecords -LogName System -StartTime (Get-Date).AddDays(-1) } |
            Should -Throw '*Unable to read the System event log*'
    }

    It 'returns Healthy when both logs contain no matching events' {
        Mock Get-EventLogRecords { @() } -ModuleName EventLogAnalyzer
        $result = Get-EventLogAnalysis
        $result.OverallStatus | Should -Be 'Healthy'
        $result.Summary.Total | Should -Be 0
    }

    It 'counts Critical, Error and Warning events' {
        Mock Get-EventLogRecords {
            if ($LogName -eq 'System') {
                @(
                    [pscustomobject]@{ TimeCreated=(Get-Date); LogName='System'; Level='Critical'; Id=41; Source='Kernel-Power'; MachineName='PC'; Message='Unexpected shutdown' }
                    [pscustomobject]@{ TimeCreated=(Get-Date).AddMinutes(-1); LogName='System'; Level='Error'; Id=1001; Source='BugCheck'; MachineName='PC'; Message='Bug check' }
                )
            }
            else {
                @([pscustomobject]@{ TimeCreated=(Get-Date); LogName='Application'; Level='Warning'; Id=1000; Source='App'; MachineName='PC'; Message='Application warning' })
            }
        } -ModuleName EventLogAnalyzer

        $result = Get-EventLogAnalysis
        $result.Summary.Total | Should -Be 3
        $result.Summary.Critical | Should -Be 1
        $result.Summary.Errors | Should -Be 1
        $result.Summary.Warnings | Should -Be 1
        $result.OverallStatus | Should -Be 'Critical'
    }

    It 'identifies recurring issues by log, source and event ID' {
        Mock Get-EventLogRecords {
            @(
                1..3 | ForEach-Object {
                    [pscustomobject]@{ TimeCreated=(Get-Date).AddMinutes(-$_); LogName=$LogName; Level='Error'; Id=7000; Source='Service Control Manager'; MachineName='PC'; Message='Service failed' }
                }
            )
        } -ModuleName EventLogAnalyzer

        $result = Get-EventLogAnalysis -LogNames System -RecurringThreshold 3
        $result.RecurringIssues.Count | Should -Be 1
        $result.RecurringIssues[0].Count | Should -Be 3
    }

    It 'returns Warning when one log fails but another is readable' {
        Mock Get-EventLogRecords {
            if ($LogName -eq 'System') { throw 'Access denied' }
            @()
        } -ModuleName EventLogAnalyzer

        $result = Get-EventLogAnalysis
        $result.OverallStatus | Should -Be 'Warning'
        $result.Errors.Count | Should -Be 1
    }

    It 'returns Unknown when all requested logs fail' {
        Mock Get-EventLogRecords { throw 'Access denied' } -ModuleName EventLogAnalyzer
        $result = Get-EventLogAnalysis
        $result.OverallStatus | Should -Be 'Unknown'
        $result.Errors.Count | Should -Be 2
    }
}
