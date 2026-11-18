Set-StrictMode -Version Latest

function Get-EventLevelName {
    param([AllowNull()][object]$Level, [AllowNull()][string]$LevelDisplayName)

    if (-not [string]::IsNullOrWhiteSpace($LevelDisplayName)) {
        return $LevelDisplayName
    }

    switch ([int]$Level) {
        1 { 'Critical' }
        2 { 'Error' }
        3 { 'Warning' }
        4 { 'Information' }
        5 { 'Verbose' }
        default { 'Unknown' }
    }
}

function Get-EventLogRecords {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('System','Application')][string]$LogName,
        [Parameter(Mandatory)][datetime]$StartTime,
        [ValidateSet('Critical','Error','Warning')][string[]]$Levels = @('Critical','Error','Warning'),
        [ValidateRange(1,10000)][int]$MaxEvents = 500
    )

    $levelMap = @{ Critical = 1; Error = 2; Warning = 3 }
    $levelIds = @($Levels | ForEach-Object { $levelMap[$_] } | Sort-Object -Unique)
    if ($levelIds.Count -eq 0) { return @() }

    try {
        $records = @(Get-WinEvent -FilterHashtable @{
            LogName   = $LogName
            StartTime = $StartTime
            Level     = $levelIds
        } -MaxEvents $MaxEvents -ErrorAction Stop)

        foreach ($record in $records) {
            $levelName = Get-EventLevelName -Level $record.Level -LevelDisplayName $record.LevelDisplayName
            [pscustomobject]@{
                TimeCreated = $record.TimeCreated
                LogName     = $LogName
                Level       = $levelName
                Id          = [int]$record.Id
                Source      = [string]$record.ProviderName
                MachineName = [string]$record.MachineName
                Message     = [string]$record.Message
            }
        }
    }
    catch {
        if ($_.FullyQualifiedErrorId -match 'NoMatchingEventsFound' -or $_.Exception.Message -match 'No events were found|No matching events') {
            return @()
        }
        throw "Unable to read the $LogName event log: $($_.Exception.Message)"
    }
}

function Get-EventLogAnalysis {
    [CmdletBinding()]
    param(
        [ValidateSet('System','Application')][string[]]$LogNames = @('System','Application'),
        [ValidateRange(1,8760)][int]$LookbackHours = 24,
        [ValidateRange(1,10000)][int]$MaxEventsPerLog = 500,
        [ValidateSet('Critical','Error','Warning')][string[]]$Levels = @('Critical','Error','Warning'),
        [ValidateRange(1,100)][int]$RecurringThreshold = 3
    )

    $startTime = (Get-Date).AddHours(-$LookbackHours)
    $allEvents = [System.Collections.Generic.List[object]]::new()
    $logResults = [System.Collections.Generic.List[object]]::new()
    $errors = [System.Collections.Generic.List[string]]::new()

    foreach ($logName in $LogNames) {
        try {
            $records = @(Get-EventLogRecords -LogName $logName -StartTime $startTime -Levels $Levels -MaxEvents $MaxEventsPerLog)
            foreach ($record in $records) { $allEvents.Add($record) }
            $logResults.Add([pscustomobject]@{
                LogName = $logName
                Status  = 'OK'
                Count   = $records.Count
                Error   = $null
            })
        }
        catch {
            $errors.Add($_.Exception.Message)
            $logResults.Add([pscustomobject]@{
                LogName = $logName
                Status  = 'Error'
                Count   = 0
                Error   = $_.Exception.Message
            })
        }
    }

    $events = @($allEvents | Sort-Object TimeCreated -Descending)
    $criticalCount = @($events | Where-Object Level -eq 'Critical').Count
    $errorCount = @($events | Where-Object Level -eq 'Error').Count
    $warningCount = @($events | Where-Object Level -eq 'Warning').Count

    $grouped = @(
        $events |
            Group-Object { '{0}|{1}|{2}' -f $_.LogName,$_.Source,$_.Id } |
            ForEach-Object {
                $first = $_.Group[0]
                [pscustomobject]@{
                    LogName = $first.LogName
                    Source  = $first.Source
                    Id      = $first.Id
                    Count   = $_.Count
                    Level   = $first.Level
                    Latest  = $first.TimeCreated
                    Message = $first.Message
                }
            } |
            Sort-Object @{ Expression = 'Count'; Descending = $true }, @{ Expression = 'Latest'; Descending = $true }
    )

    $recurring = @($grouped | Where-Object Count -ge $RecurringThreshold)
    $topIssues = @($grouped | Select-Object -First 10)

    if ($errors.Count -eq $LogNames.Count) {
        $overallStatus = 'Unknown'
    }
    elseif ($criticalCount -gt 0) {
        $overallStatus = 'Critical'
    }
    elseif ($errorCount -gt 0 -or $warningCount -gt 0 -or $errors.Count -gt 0) {
        $overallStatus = 'Warning'
    }
    else {
        $overallStatus = 'Healthy'
    }

    [pscustomobject]@{
        CollectedAt     = Get-Date
        StartTime       = $startTime
        LookbackHours   = $LookbackHours
        Events          = $events
        LogResults      = @($logResults)
        Summary         = [pscustomobject]@{
            Total    = $events.Count
            Critical = $criticalCount
            Errors   = $errorCount
            Warnings = $warningCount
        }
        TopIssues       = $topIssues
        RecurringIssues = $recurring
        Errors          = @($errors)
        OverallStatus   = $overallStatus
    }
}

Export-ModuleMember -Function Get-EventLogRecords, Get-EventLogAnalysis
