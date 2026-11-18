Set-StrictMode -Version Latest

function Get-OverallHealthAssessment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Components
    )

    $validStatuses = @('Healthy','Warning','Critical','Unknown')
    $normalized = @($Components | ForEach-Object {
        $status = [string]$_.Status
        if ($status -notin $validStatuses) { $status = 'Unknown' }
        [pscustomobject]@{
            Name = [string]$_.Name
            Status = $status
            Details = [string]$_.Details
        }
    })

    if ($normalized.Count -eq 0 -or @($normalized | Where-Object Status -ne 'Unknown').Count -eq 0) {
        $overall = 'Unknown'
    }
    elseif ($normalized.Status -contains 'Critical') {
        $overall = 'Critical'
    }
    elseif ($normalized.Status -contains 'Warning' -or $normalized.Status -contains 'Unknown') {
        $overall = 'Warning'
    }
    else {
        $overall = 'Healthy'
    }

    $recommendations = [System.Collections.Generic.List[string]]::new()
    foreach ($component in $normalized) {
        switch ($component.Name) {
            'Resources' {
                if ($component.Status -eq 'Critical') { $recommendations.Add('Review CPU, memory and disk findings immediately; close unnecessary workloads or free disk space as appropriate.') }
                elseif ($component.Status -eq 'Warning') { $recommendations.Add('Review resource warnings and identify processes or volumes approaching configured thresholds.') }
                elseif ($component.Status -eq 'Unknown') { $recommendations.Add('Resource metrics were incomplete; rerun the check and verify access to performance and storage data.') }
            }
            'Services' {
                if ($component.Status -eq 'Warning' -or $component.Status -eq 'Critical') { $recommendations.Add('Review affected automatic-start services and their dependencies before taking action.') }
                elseif ($component.Status -eq 'Unknown') { $recommendations.Add('Service inventory could not be fully assessed; verify permissions and the Service Control Manager.') }
            }
            'Windows Update' {
                if ($component.Status -eq 'Warning' -or $component.Status -eq 'Critical') { $recommendations.Add('Review failed or aborted updates and pending-reboot indicators in Windows Update Monitor.') }
                elseif ($component.Status -eq 'Unknown') { $recommendations.Add('Windows Update history was unavailable; verify the Windows Update components and retry.') }
            }
            'Event Logs' {
                if ($component.Status -eq 'Warning' -or $component.Status -eq 'Critical') { $recommendations.Add('Inspect recurring Error and Critical events in Event Log Analysis; correlate timestamps with symptoms.') }
                elseif ($component.Status -eq 'Unknown') { $recommendations.Add('Event logs could not be fully read; verify event-log service state and permissions.') }
            }
        }
    }

    if ($recommendations.Count -eq 0 -and $overall -eq 'Healthy') {
        $recommendations.Add('No health warnings were detected by the configured checks. Continue routine monitoring.')
    }
    elseif ($overall -eq 'Unknown' -and $recommendations.Count -eq 0) {
        $recommendations.Add('No component could be assessed. Check permissions and module availability, then run the health check again.')
    }

    [pscustomobject]@{
        OverallStatus = $overall
        Components = $normalized
        Counts = [pscustomobject]@{
            Healthy = @($normalized | Where-Object Status -eq 'Healthy').Count
            Warning = @($normalized | Where-Object Status -eq 'Warning').Count
            Critical = @($normalized | Where-Object Status -eq 'Critical').Count
            Unknown = @($normalized | Where-Object Status -eq 'Unknown').Count
        }
        Recommendations = @($recommendations)
        AssessedAt = Get-Date
    }
}

function Invoke-FullSystemHealthCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Thresholds,
        [string[]]$ServiceNames = @(),
        [ValidateRange(1,500)][int]$UpdateHistoryLimit = 20,
        [ValidateRange(1,8760)][int]$EventLookbackHours = 24,
        [ValidateRange(1,10000)][int]$MaxEventsPerLog = 500,
        [ValidateSet('Critical','Error','Warning')][string[]]$EventLevels = @('Critical','Error','Warning')
    )

    $resource = $null; $services = $null; $updates = $null; $events = $null
    $componentResults = [System.Collections.Generic.List[object]]::new()

    try {
        $resource = Invoke-ResourceMonitoring -Thresholds $Thresholds
        $componentResults.Add([pscustomobject]@{ Name='Resources'; Status=[string]$resource.Assessment.OverallStatus; Details=('CPU {0}% | Memory {1}% | Disks {2}' -f $resource.Cpu.UsagePercent,$resource.Memory.UsagePercent,$resource.Disks.Count) })
    } catch {
        $componentResults.Add([pscustomobject]@{ Name='Resources'; Status='Unknown'; Details=$_.Exception.Message })
    }

    try {
        if ($ServiceNames.Count -gt 0) { $services = Invoke-ServiceMonitoring -ServiceNames $ServiceNames }
        else { $services = Invoke-ServiceMonitoring }
        $serviceStatus = [string]$services.Assessment.OverallStatus
        if ($serviceStatus -eq 'Info') { $serviceStatus = 'Healthy' }
        $componentResults.Add([pscustomobject]@{ Name='Services'; Status=$serviceStatus; Details=('{0} total | {1} running | {2} stopped | {3} warnings' -f $services.Assessment.Total,$services.Assessment.Running,$services.Assessment.Stopped,$services.Assessment.Warnings) })
    } catch {
        $componentResults.Add([pscustomobject]@{ Name='Services'; Status='Unknown'; Details=$_.Exception.Message })
    }

    try {
        $updates = Invoke-WindowsUpdateMonitoring -HistoryLimit $UpdateHistoryLimit
        $componentResults.Add([pscustomobject]@{ Name='Windows Update'; Status=[string]$updates.OverallStatus; Details=('{0} history entries | {1} failed/aborted | Pending reboot: {2}' -f $updates.History.Count,$updates.FailedUpdates.Count,$updates.PendingReboot.IsPending) })
    } catch {
        $componentResults.Add([pscustomobject]@{ Name='Windows Update'; Status='Unknown'; Details=$_.Exception.Message })
    }

    try {
        $events = Get-EventLogAnalysis -LogNames @('System','Application') -LookbackHours $EventLookbackHours -MaxEventsPerLog $MaxEventsPerLog -Levels $EventLevels
        $componentResults.Add([pscustomobject]@{ Name='Event Logs'; Status=[string]$events.OverallStatus; Details=('{0} events | {1} critical | {2} errors | {3} warnings' -f $events.Summary.Total,$events.Summary.Critical,$events.Summary.Errors,$events.Summary.Warnings) })
    } catch {
        $componentResults.Add([pscustomobject]@{ Name='Event Logs'; Status='Unknown'; Details=$_.Exception.Message })
    }

    $assessment = Get-OverallHealthAssessment -Components @($componentResults)
    [pscustomobject]@{
        CollectedAt = Get-Date
        Resource = $resource
        Services = $services
        WindowsUpdate = $updates
        EventLogs = $events
        Assessment = $assessment
    }
}

Export-ModuleMember -Function Get-OverallHealthAssessment, Invoke-FullSystemHealthCheck
