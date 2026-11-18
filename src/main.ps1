#requires -Version 7.0
[CmdletBinding()]
param([switch]$NoColor)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:AppRoot = Split-Path -Parent $PSScriptRoot
$script:ConfigPath = Join-Path $script:AppRoot 'config/settings.json'
$script:LogDirectory = Join-Path $script:AppRoot 'logs'
$script:LogPath = Join-Path $script:LogDirectory ("whm-{0}.log" -f (Get-Date -Format 'yyyyMMdd'))
$script:Settings = $null
$script:LatestResourceResult = $null

. (Join-Path $PSScriptRoot 'core/Console.ps1')
. (Join-Path $PSScriptRoot 'core/Logger.ps1')
. (Join-Path $PSScriptRoot 'core/Config.ps1')
Import-Module (Join-Path $PSScriptRoot 'modules/SystemMonitor.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'modules/WindowsServicesMonitor.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'modules/WindowsUpdateMonitor.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'modules/EventLogAnalyzer.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'modules/HealthCheck.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'modules/ReportGenerator.psm1') -Force

function Initialize-Application {
    New-Item -ItemType Directory -Path $script:LogDirectory -Force | Out-Null
    Initialize-Logger -Path $script:LogPath
    $script:Settings = Get-AppSettings -Path $script:ConfigPath
    Write-Log -Level INFO -Message 'Application started.'
    Write-Log -Level INFO -Message ("PowerShell version: {0}" -f $PSVersionTable.PSVersion)
}

function Show-Placeholder {
    param([Parameter(Mandatory)][string]$Title,[Parameter(Mandatory)][string]$Description)
    Clear-Console
    Write-Section $Title
    Write-Host ''
    Write-Host $Description -ForegroundColor Gray
    Write-Host ''
    Write-Host 'This module is scheduled for a later development phase.' -ForegroundColor Yellow
    Read-EnterToContinue
}

function Show-SystemInformation {
    Clear-Console
    Write-Section 'SYSTEM INFORMATION'
    try {
        $info = Get-SystemInformation
        $info | Format-List ComputerName,Manufacturer,Model,OperatingSystem,OSVersion,BuildNumber,Architecture,ProcessorName,LogicalProcessors,TotalPhysicalMemoryGB,LastBootTime,Uptime | Out-Host
        Write-Log INFO 'System information collected.'
    } catch {
        Write-Log ERROR $_.Exception.Message
        Write-Host $_.Exception.Message -ForegroundColor Red
    }
    Read-EnterToContinue
}

function Show-ResourceMonitoring {
    Clear-Console
    Write-Section 'RESOURCE MONITORING'
    $result = Invoke-ResourceMonitoring -Thresholds $script:Settings.thresholds
    $script:LatestResourceResult = $result

    Write-Host ''
    Write-Host 'CPU' -ForegroundColor Cyan
    if ($result.Cpu.Status -eq 'OK') {
        Write-Host ("  Usage: {0}%" -f $result.Cpu.UsagePercent)
    } else {
        Write-Host ("  Unknown: {0}" -f $result.Cpu.ErrorMessage) -ForegroundColor Yellow
    }

    Write-Host ''
    Write-Host 'MEMORY' -ForegroundColor Cyan
    if ($result.Memory.Status -eq 'OK') {
        Write-Host ("  Used: {0} GB / {1} GB ({2}%) | Available: {3} GB" -f $result.Memory.UsedGB,$result.Memory.TotalGB,$result.Memory.UsagePercent,$result.Memory.AvailableGB)
    } else {
        Write-Host ("  Unknown: {0}" -f $result.Memory.ErrorMessage) -ForegroundColor Yellow
    }

    Write-Host ''
    Write-Host 'FIXED DISKS' -ForegroundColor Cyan
    $result.Disks | Format-Table Drive,FileSystem,SizeGB,UsedGB,FreeGB,FreePercent,Status -AutoSize | Out-Host

    Write-Host ''
    $color = switch ($result.Assessment.OverallStatus) {
        'Healthy' { 'Green' }
        'Warning' { 'Yellow' }
        'Critical' { 'Red' }
        default { 'DarkYellow' }
    }
    Write-Host ("OVERALL RESOURCE STATUS: {0}" -f $result.Assessment.OverallStatus.ToUpperInvariant()) -ForegroundColor $color
    $result.Assessment.Findings | Format-Table Component,Status,Message -AutoSize -Wrap | Out-Host
    Write-Log INFO ("Resource monitoring completed. Overall status: {0}" -f $result.Assessment.OverallStatus)
    Read-EnterToContinue
}

function Show-WindowsServices {
    Clear-Console
    Write-Section 'WINDOWS SERVICES MONITOR'

    try {
        $configuredServices = @($script:Settings.services.monitorList)
        $result = Invoke-ServiceMonitoring -ServiceNames $configuredServices
        $view = 'Configured monitored services'

        Write-Host ''
        Write-Host 'Monitored services are defined in config/settings.json.' -ForegroundColor DarkGray
        $choice = (Read-Host 'Press A to show all services, S to show stopped services only, or Enter for monitored services').Trim().ToUpperInvariant()

        if ($choice -eq 'A') {
            $result = Invoke-ServiceMonitoring
            $view = 'All Windows services'
        }
        elseif ($choice -eq 'S') {
            $result.Services = @($result.Services | Where-Object Status -eq 'Stopped')
            $result.Assessment = Get-ServiceHealthAssessment -Services $result.Services
            $view = 'Stopped monitored services'
        }

        Write-Host ''
        Write-Host $view -ForegroundColor Cyan
        Write-Host ('Total: {0} | Running: {1} | Stopped: {2} | Warnings: {3}' -f $result.Assessment.Total,$result.Assessment.Running,$result.Assessment.Stopped,$result.Assessment.Warnings)
        Write-Host ''

        if ($result.Services.Count -gt 0) {
            $result.Assessment.Findings | Format-Table Name,Status,StartupType,Health,Message -AutoSize -Wrap | Out-Host
        }
        else {
            Write-Host 'No services matched this view.' -ForegroundColor DarkGray
        }

        $color = switch ($result.Assessment.OverallStatus) {
            'Healthy' { 'Green' }
            'Warning' { 'Yellow' }
            'Unknown' { 'DarkYellow' }
            default { 'Gray' }
        }
        Write-Host ("OVERALL SERVICE STATUS: {0}" -f $result.Assessment.OverallStatus.ToUpperInvariant()) -ForegroundColor $color
        Write-Log INFO ("Windows services checked. View: {0}; Total: {1}; Warnings: {2}" -f $view,$result.Assessment.Total,$result.Assessment.Warnings)
    }
    catch {
        Write-Log ERROR $_.Exception.Message
        Write-Host ("Unable to check Windows services: {0}" -f $_.Exception.Message) -ForegroundColor Red
    }

    Read-EnterToContinue
}

function Show-WindowsUpdate {
    Clear-Console
    Write-Section 'WINDOWS UPDATE MONITOR'

    $historyLimit = 20
    if ($script:Settings.ContainsKey('windowsUpdate') -and $script:Settings.windowsUpdate.historyLimit) {
        $historyLimit = [int]$script:Settings.windowsUpdate.historyLimit
    }

    try {
        $result = Invoke-WindowsUpdateMonitoring -HistoryLimit $historyLimit

        Write-Host ''
        Write-Host 'UPDATE HISTORY' -ForegroundColor Cyan
        if ($result.HistoryStatus -eq 'OK') {
            Write-Host ("Entries checked: {0} | Failed/Aborted: {1}" -f $result.History.Count,$result.FailedUpdates.Count)
            if ($result.History.Count -gt 0) {
                $result.History | Select-Object -First $historyLimit Date,Result,Title | Format-Table -AutoSize -Wrap | Out-Host
            }
            else {
                Write-Host 'No update history entries were found.' -ForegroundColor DarkGray
            }
        }
        else {
            Write-Host ("History unavailable: {0}" -f $result.HistoryError) -ForegroundColor Yellow
        }

        Write-Host ''
        Write-Host 'PENDING REBOOT' -ForegroundColor Cyan
        if ($result.PendingReboot.IsPending) {
            Write-Host 'A reboot appears to be pending.' -ForegroundColor Yellow
            foreach ($indicator in $result.PendingReboot.Indicators) {
                Write-Host ("  - {0}" -f $indicator) -ForegroundColor Yellow
            }
        }
        else {
            Write-Host 'No pending reboot indicators were detected.' -ForegroundColor Green
        }

        $color = switch ($result.OverallStatus) {
            'Healthy' { 'Green' }
            'Warning' { 'Yellow' }
            default { 'DarkYellow' }
        }
        Write-Host ''
        Write-Host ("OVERALL WINDOWS UPDATE STATUS: {0}" -f $result.OverallStatus.ToUpperInvariant()) -ForegroundColor $color
        Write-Log INFO ("Windows Update check completed. History status: {0}; Failed updates: {1}; Pending reboot: {2}; Overall: {3}" -f $result.HistoryStatus,$result.FailedUpdates.Count,$result.PendingReboot.IsPending,$result.OverallStatus)
    }
    catch {
        Write-Log ERROR $_.Exception.Message
        Write-Host ("Unable to complete Windows Update checks: {0}" -f $_.Exception.Message) -ForegroundColor Red
    }

    Read-EnterToContinue
}


function Show-EventLogAnalysis {
    Clear-Console
    Write-Section 'EVENT LOG ANALYSIS'

    $eventSettings = $script:Settings.eventLog
    $lookbackHours = [int]$eventSettings.lookbackHours
    $maxEvents = [int]$eventSettings.maxEventsPerLog
    $levels = @($eventSettings.levels)

    try {
        $result = Get-EventLogAnalysis -LogNames @('System','Application') `
            -LookbackHours $lookbackHours -MaxEventsPerLog $maxEvents -Levels $levels

        Write-Host ''
        Write-Host ("LOOKBACK WINDOW: Last {0} hours" -f $result.LookbackHours) -ForegroundColor DarkGray
        Write-Host ("EVENT SUMMARY | Total: {0} | Critical: {1} | Error: {2} | Warning: {3}" -f `
            $result.Summary.Total,$result.Summary.Critical,$result.Summary.Errors,$result.Summary.Warnings)

        Write-Host ''
        Write-Host 'LOG COLLECTION' -ForegroundColor Cyan
        $result.LogResults | Format-Table LogName,Status,Count,Error -AutoSize -Wrap | Out-Host

        Write-Host ''
        Write-Host 'RECENT EVENTS' -ForegroundColor Cyan
        if ($result.Events.Count -gt 0) {
            $result.Events | Select-Object -First 20 TimeCreated,Level,LogName,Id,Source,Message |
                Format-Table -AutoSize -Wrap | Out-Host
        }
        else {
            Write-Host 'No matching Critical, Error or Warning events were found.' -ForegroundColor Green
        }

        Write-Host ''
        Write-Host 'RECURRING ISSUES' -ForegroundColor Cyan
        if ($result.RecurringIssues.Count -gt 0) {
            $result.RecurringIssues | Format-Table LogName,Source,Id,Level,Count,Latest -AutoSize -Wrap | Out-Host
        }
        else {
            Write-Host 'No recurring issues reached the configured threshold (3 occurrences).' -ForegroundColor DarkGray
        }

        $color = switch ($result.OverallStatus) {
            'Healthy' { 'Green' }
            'Warning' { 'Yellow' }
            'Critical' { 'Red' }
            default { 'DarkYellow' }
        }
        Write-Host ''
        Write-Host ("OVERALL EVENT LOG STATUS: {0}" -f $result.OverallStatus.ToUpperInvariant()) -ForegroundColor $color

        foreach ($errorMessage in $result.Errors) {
            Write-Host ("Collection issue: {0}" -f $errorMessage) -ForegroundColor Yellow
        }

        Write-Log INFO ("Event log analysis completed. Events: {0}; Critical: {1}; Errors: {2}; Warnings: {3}; Overall: {4}" -f `
            $result.Summary.Total,$result.Summary.Critical,$result.Summary.Errors,$result.Summary.Warnings,$result.OverallStatus)
    }
    catch {
        Write-Log ERROR $_.Exception.Message
        Write-Host ("Unable to analyze Windows event logs: {0}" -f $_.Exception.Message) -ForegroundColor Red
    }

    Read-EnterToContinue
}

function Show-FullSystemHealthCheck {
    Clear-Console
    Write-Section 'FULL SYSTEM HEALTH CHECK'
    Write-Host 'Running read-only diagnostics across resources, services, Windows Update and event logs...' -ForegroundColor DarkGray

    try {
        $eventSettings = $script:Settings.eventLog
        $historyLimit = 20
        if ($script:Settings.ContainsKey('windowsUpdate') -and $script:Settings.windowsUpdate.historyLimit) {
            $historyLimit = [int]$script:Settings.windowsUpdate.historyLimit
        }

        $result = Invoke-FullSystemHealthCheck `
            -Thresholds $script:Settings.thresholds `
            -ServiceNames @($script:Settings.services.monitorList) `
            -UpdateHistoryLimit $historyLimit `
            -EventLookbackHours ([int]$eventSettings.lookbackHours) `
            -MaxEventsPerLog ([int]$eventSettings.maxEventsPerLog) `
            -EventLevels @($eventSettings.levels)

        Write-Host ''
        Write-Host 'COMPONENT HEALTH SUMMARY' -ForegroundColor Cyan
        $result.Assessment.Components | Format-Table Name,Status,Details -AutoSize -Wrap | Out-Host

        Write-Host ''
        Write-Host ('COMPONENT COUNTS | Healthy: {0} | Warning: {1} | Critical: {2} | Unknown: {3}' -f `
            $result.Assessment.Counts.Healthy,$result.Assessment.Counts.Warning,
            $result.Assessment.Counts.Critical,$result.Assessment.Counts.Unknown)

        $color = switch ($result.Assessment.OverallStatus) {
            'Healthy' { 'Green' }
            'Warning' { 'Yellow' }
            'Critical' { 'Red' }
            default { 'DarkYellow' }
        }
        Write-Host ''
        Write-Host ('OVERALL SYSTEM HEALTH: {0}' -f $result.Assessment.OverallStatus.ToUpperInvariant()) -ForegroundColor $color

        Write-Host ''
        Write-Host 'TROUBLESHOOTING RECOMMENDATIONS' -ForegroundColor Cyan
        foreach ($recommendation in $result.Assessment.Recommendations) {
            Write-Host ("  - {0}" -f $recommendation)
        }

        Write-Log INFO ("Full system health check completed. Overall: {0}; Healthy: {1}; Warning: {2}; Critical: {3}; Unknown: {4}" -f `
            $result.Assessment.OverallStatus,$result.Assessment.Counts.Healthy,$result.Assessment.Counts.Warning,
            $result.Assessment.Counts.Critical,$result.Assessment.Counts.Unknown)
    }
    catch {
        Write-Log ERROR $_.Exception.Message
        Write-Host ("Unable to complete full system health check: {0}" -f $_.Exception.Message) -ForegroundColor Red
    }

    Read-EnterToContinue
}


function Show-Reports {
    Clear-Console
    Write-Section 'REPORT GENERATION / VIEWER'

    $relativeOutput = 'reports'
    if ($script:Settings.ContainsKey('reporting') -and $script:Settings.reporting.outputDirectory) {
        $relativeOutput = [string]$script:Settings.reporting.outputDirectory
    }
    $outputDirectory = if ([System.IO.Path]::IsPathRooted($relativeOutput)) { $relativeOutput } else { Join-Path $script:AppRoot $relativeOutput }

    Write-Host ''
    Write-Host '[G] Generate a new health report' -ForegroundColor Cyan
    Write-Host '[V] View the latest HTML report' -ForegroundColor Cyan
    Write-Host '[B] Back to main menu' -ForegroundColor DarkGray
    $choice = (Read-Host 'Select an option').Trim().ToUpperInvariant()

    if ($choice -eq 'B' -or [string]::IsNullOrWhiteSpace($choice)) { return }

    if ($choice -eq 'V') {
        $latest = Get-ChildItem -LiteralPath $outputDirectory -Filter 'health-report-*.html' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($null -eq $latest) {
            Write-Host 'No HTML report found. Generate a report first.' -ForegroundColor Yellow
        }
        else {
            Write-Host ("Opening: {0}" -f $latest.FullName) -ForegroundColor Green
            Start-Process -FilePath $latest.FullName
            Write-Log INFO ("Opened health report: {0}" -f $latest.FullName)
        }
        Read-EnterToContinue
        return
    }

    if ($choice -ne 'G') {
        Write-Host 'Invalid selection.' -ForegroundColor Red
        Read-EnterToContinue
        return
    }

    try {
        Write-Host ''
        Write-Host 'Collecting fresh diagnostics before generating the report...' -ForegroundColor DarkGray
        $eventSettings = $script:Settings.eventLog
        $historyLimit = 20
        if ($script:Settings.ContainsKey('windowsUpdate') -and $script:Settings.windowsUpdate.historyLimit) {
            $historyLimit = [int]$script:Settings.windowsUpdate.historyLimit
        }
        $healthResult = Invoke-FullSystemHealthCheck `
            -Thresholds $script:Settings.thresholds `
            -ServiceNames @($script:Settings.services.monitorList) `
            -UpdateHistoryLimit $historyLimit `
            -EventLookbackHours ([int]$eventSettings.lookbackHours) `
            -MaxEventsPerLog ([int]$eventSettings.maxEventsPerLog) `
            -EventLevels @($eventSettings.levels)

        $formats = @('html','json','csv')
        if ($script:Settings.ContainsKey('reporting') -and $script:Settings.reporting.formats) {
            $formats = @($script:Settings.reporting.formats | ForEach-Object { ([string]$_).ToLowerInvariant() })
        }
        $report = New-HealthReport -HealthCheckResult $healthResult -OutputDirectory $outputDirectory -Formats $formats

        Write-Host ''
        Write-Host 'REPORT GENERATED SUCCESSFULLY' -ForegroundColor Green
        Write-Host ("Overall health: {0}" -f $healthResult.Assessment.OverallStatus)
        foreach ($property in @('Html','Json','Csv')) {
            $path = $report.Files.$property
            if ($path) { Write-Host ("{0}: {1}" -f $property,$path) }
        }
        Write-Log INFO ("Health report generated. Overall: {0}; Directory: {1}" -f $healthResult.Assessment.OverallStatus,$outputDirectory)

        if ($report.Files.Html) {
            $openChoice = (Read-Host 'Open the HTML report now? (Y/N)').Trim().ToUpperInvariant()
            if ($openChoice -eq 'Y') { Start-Process -FilePath $report.Files.Html }
        }
    }
    catch {
        Write-Log ERROR ("Report generation failed: {0}" -f $_.Exception.Message)
        Write-Host ("Unable to generate report: {0}" -f $_.Exception.Message) -ForegroundColor Red
    }
    Read-EnterToContinue
}

function Show-Settings {
    Clear-Console
    Write-Section 'SETTINGS'
    Write-Host ''
    Write-Host ("CPU warning threshold       : {0}%" -f $script:Settings.thresholds.cpuWarning)
    Write-Host ("CPU critical threshold      : {0}%" -f $script:Settings.thresholds.cpuCritical)
    Write-Host ("Memory warning threshold   : {0}%" -f $script:Settings.thresholds.memoryWarning)
    Write-Host ("Memory critical threshold  : {0}%" -f $script:Settings.thresholds.memoryCritical)
    Write-Host ("Disk free warning threshold: {0}%" -f $script:Settings.thresholds.diskFreeWarning)
    Write-Host ("Disk free critical threshold: {0}%" -f $script:Settings.thresholds.diskFreeCritical)
    Write-Host ("Event lookback              : {0} hours" -f $script:Settings.eventLog.lookbackHours)
    if ($script:Settings.ContainsKey('windowsUpdate')) { Write-Host ("Windows Update history limit: {0}" -f $script:Settings.windowsUpdate.historyLimit) }
    Write-Host ''
    Write-Host ("Configuration: {0}" -f $script:ConfigPath) -ForegroundColor DarkGray
    Read-EnterToContinue
}

function Invoke-MenuAction {
    param([Parameter(Mandatory)][string]$Choice)
    switch ($Choice) {
        '1' { Show-SystemInformation }
        '2' { Show-ResourceMonitoring }
        '3' { Show-WindowsServices }
        '4' { Show-WindowsUpdate }
        '5' { Show-EventLogAnalysis }
        '6' { Show-FullSystemHealthCheck }
        '7' { Show-Reports }
        '8' { Show-Settings }
        '0' { return $false }
        default {
            Write-Host 'Invalid selection. Choose a number from 0 to 8.' -ForegroundColor Red
            Start-Sleep -Milliseconds 900
        }
    }
    return $true
}

try {
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        throw 'Windows Health Monitor requires PowerShell 7 or later.'
    }
    Initialize-Application
    $running = $true
    while ($running) {
        Clear-Console
        Show-Banner
        Show-MainMenu
        $choice = Read-MenuChoice
        try { $running = Invoke-MenuAction -Choice $choice }
        catch {
            Write-Log ERROR $_.Exception.Message
            Write-Host ("Unexpected error: {0}" -f $_.Exception.Message) -ForegroundColor Red
            Read-EnterToContinue
        }
    }
    Write-Log INFO 'Application exited normally.'
    Clear-Console
    Write-Host 'Thank you for using Windows Health Monitor.' -ForegroundColor Green
}
catch {
    Write-Error $_
    if (Test-Path $script:LogDirectory) { Write-Log ERROR $_.Exception.Message }
    exit 1
}
