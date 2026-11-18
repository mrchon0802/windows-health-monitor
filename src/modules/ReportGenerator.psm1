Set-StrictMode -Version Latest

function ConvertTo-ReportHtmlText {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return '' }
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function New-ReportTable {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rows,
        [Parameter(Mandatory)][string[]]$Properties,
        [string[]]$Headers = $Properties
    )
    if ($Rows.Count -eq 0) { return '<p class="muted">No data available.</p>' }
    $builder = [System.Text.StringBuilder]::new()
    [void]$builder.Append('<div class="table-wrap"><table><thead><tr>')
    foreach ($header in $Headers) { [void]$builder.Append('<th>' + (ConvertTo-ReportHtmlText $header) + '</th>') }
    [void]$builder.Append('</tr></thead><tbody>')
    foreach ($row in $Rows) {
        [void]$builder.Append('<tr>')
        foreach ($property in $Properties) {
            $value = $row.$property
            if ($value -is [datetime]) { $value = $value.ToString('yyyy-MM-dd HH:mm:ss') }
            [void]$builder.Append('<td>' + (ConvertTo-ReportHtmlText $value) + '</td>')
        }
        [void]$builder.Append('</tr>')
    }
    [void]$builder.Append('</tbody></table></div>')
    return $builder.ToString()
}

function New-HealthReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$HealthCheckResult,
        [Parameter(Mandatory)][string]$OutputDirectory,
        [ValidateSet('html','json','csv')][string[]]$Formats = @('html','json','csv')
    )

    $resolvedDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
    New-Item -ItemType Directory -Path $resolvedDirectory -Force | Out-Null
    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $baseName = "health-report-$stamp"
    $paths = [ordered]@{}

    $components = @($HealthCheckResult.Assessment.Components)
    $assessment = $HealthCheckResult.Assessment
    $computerName = [string]$env:COMPUTERNAME
    if ([string]::IsNullOrWhiteSpace($computerName)) { $computerName = 'Unknown' }

    if ($Formats -contains 'json') {
        $jsonPath = Join-Path $resolvedDirectory "$baseName.json"
        $HealthCheckResult | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $jsonPath -Encoding utf8
        $paths['Json'] = $jsonPath
    }

    if ($Formats -contains 'csv') {
        $csvPath = Join-Path $resolvedDirectory "$baseName.csv"
        $components | Select-Object Name,Status,Details | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding utf8
        $paths['Csv'] = $csvPath
    }

    if ($Formats -contains 'html') {
        $htmlPath = Join-Path $resolvedDirectory "$baseName.html"
        $status = ConvertTo-ReportHtmlText $assessment.OverallStatus
        $statusClass = switch ([string]$assessment.OverallStatus) {
            'Healthy' { 'healthy' }
            'Warning' { 'warning' }
            'Critical' { 'critical' }
            default { 'unknown' }
        }
        $componentHtml = New-ReportTable -Rows $components -Properties @('Name','Status','Details') -Headers @('Component','Status','Details')
        $recommendationHtml = if (@($assessment.Recommendations).Count -gt 0) {
            '<ul>' + ((@($assessment.Recommendations) | ForEach-Object { '<li>' + (ConvertTo-ReportHtmlText $_) + '</li>' }) -join '') + '</ul>'
        } else { '<p class="muted">No recommendations.</p>' }

        $resourceHtml = '<p class="muted">Resource details unavailable.</p>'
        if ($null -ne $HealthCheckResult.Resource) {
            $resourceRows = [System.Collections.Generic.List[object]]::new()
            if ($null -ne $HealthCheckResult.Resource.Cpu) {
                $resourceRows.Add([pscustomobject]@{ Metric='CPU usage'; Value=$(if ($HealthCheckResult.Resource.Cpu.Status -eq 'OK') { "$($HealthCheckResult.Resource.Cpu.UsagePercent)%" } else { 'Unavailable' }); Status=$HealthCheckResult.Resource.Cpu.Status })
            }
            if ($null -ne $HealthCheckResult.Resource.Memory) {
                $resourceRows.Add([pscustomobject]@{ Metric='Memory usage'; Value=$(if ($HealthCheckResult.Resource.Memory.Status -eq 'OK') { "$($HealthCheckResult.Resource.Memory.UsagePercent)% ($($HealthCheckResult.Resource.Memory.UsedGB) / $($HealthCheckResult.Resource.Memory.TotalGB) GB)" } else { 'Unavailable' }); Status=$HealthCheckResult.Resource.Memory.Status })
            }
            foreach ($disk in @($HealthCheckResult.Resource.Disks)) {
                $resourceRows.Add([pscustomobject]@{ Metric="Disk $($disk.Drive) free space"; Value="$($disk.FreeGB) GB ($($disk.FreePercent)%)"; Status=$disk.Status })
            }
            $resourceHtml = New-ReportTable -Rows @($resourceRows) -Properties @('Metric','Value','Status')
        }

        $serviceHtml = '<p class="muted">Service details unavailable.</p>'
        if ($null -ne $HealthCheckResult.Services) {
            $serviceHtml = New-ReportTable -Rows @($HealthCheckResult.Services.Assessment.Findings) -Properties @('Name','Status','StartupType','Health','Message')
        }

        $updateHtml = '<p class="muted">Windows Update details unavailable.</p>'
        if ($null -ne $HealthCheckResult.WindowsUpdate) {
            $updateRows = @($HealthCheckResult.WindowsUpdate.History | Select-Object -First 20 Date,Result,Title)
            $updateHtml = '<p><strong>Pending reboot:</strong> ' + (ConvertTo-ReportHtmlText $HealthCheckResult.WindowsUpdate.PendingReboot.IsPending) + '</p>' + (New-ReportTable -Rows $updateRows -Properties @('Date','Result','Title'))
        }

        $eventHtml = '<p class="muted">Event log details unavailable.</p>'
        if ($null -ne $HealthCheckResult.EventLogs) {
            $eventSummary = $HealthCheckResult.EventLogs.Summary
            $eventHtml = '<p>Total: <strong>' + (ConvertTo-ReportHtmlText $eventSummary.Total) + '</strong> · Critical: <strong>' + (ConvertTo-ReportHtmlText $eventSummary.Critical) + '</strong> · Errors: <strong>' + (ConvertTo-ReportHtmlText $eventSummary.Errors) + '</strong> · Warnings: <strong>' + (ConvertTo-ReportHtmlText $eventSummary.Warnings) + '</strong></p>' + (New-ReportTable -Rows @($HealthCheckResult.EventLogs.RecurringIssues) -Properties @('LogName','Source','Id','Level','Count','Latest'))
        }

        $generatedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        $html = @"
<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Windows Health Monitor - $computerName</title>
<style>
:root{font-family:Segoe UI,Arial,sans-serif;color:#172033;background:#f3f5f9}*{box-sizing:border-box}body{margin:0;padding:32px}.container{max-width:1100px;margin:auto}.header{display:flex;justify-content:space-between;gap:20px;align-items:flex-start;margin-bottom:24px}.eyebrow{color:#64748b;text-transform:uppercase;letter-spacing:.12em;font-size:12px;font-weight:700}h1{margin:6px 0;font-size:30px}.muted{color:#64748b}.meta{font-size:13px;color:#64748b;line-height:1.8}.status{display:inline-block;padding:8px 14px;border-radius:999px;font-weight:700;background:#e2e8f0}.healthy{color:#166534;background:#dcfce7}.warning{color:#92400e;background:#fef3c7}.critical{color:#991b1b;background:#fee2e2}.unknown{color:#475569;background:#e2e8f0}.cards{display:grid;grid-template-columns:repeat(4,1fr);gap:14px;margin:18px 0 26px}.card,section{background:#fff;border:1px solid #e2e8f0;border-radius:14px;padding:18px;box-shadow:0 2px 8px #0f172a08}.card span{display:block;color:#64748b;font-size:13px}.card strong{display:block;font-size:28px;margin-top:5px}section{margin:16px 0}h2{font-size:18px;margin:0 0 14px}.table-wrap{overflow-x:auto}table{width:100%;border-collapse:collapse;font-size:13px}th,td{text-align:left;padding:10px;border-bottom:1px solid #e2e8f0;vertical-align:top}th{background:#f8fafc;color:#475569}td{overflow-wrap:anywhere}li{margin:8px 0;line-height:1.5}.footer{color:#94a3b8;font-size:12px;text-align:center;margin:26px 0}@media(max-width:700px){body{padding:16px}.header{display:block}.cards{grid-template-columns:repeat(2,1fr)}h1{font-size:24px}}
</style></head><body><main class="container">
<header class="header"><div><div class="eyebrow">Windows Health Monitor</div><h1>System Health Report</h1><div class="meta">Computer: $(ConvertTo-ReportHtmlText $computerName)<br>Generated: $generatedAt</div></div><div class="status $statusClass">$status</div></header>
<div class="cards"><div class="card"><span>Healthy components</span><strong>$(ConvertTo-ReportHtmlText $assessment.Counts.Healthy)</strong></div><div class="card"><span>Warnings</span><strong>$(ConvertTo-ReportHtmlText $assessment.Counts.Warning)</strong></div><div class="card"><span>Critical</span><strong>$(ConvertTo-ReportHtmlText $assessment.Counts.Critical)</strong></div><div class="card"><span>Unknown</span><strong>$(ConvertTo-ReportHtmlText $assessment.Counts.Unknown)</strong></div></div>
<section><h2>Component health summary</h2>$componentHtml</section>
<section><h2>Troubleshooting recommendations</h2>$recommendationHtml</section>
<section><h2>Resource details</h2>$resourceHtml</section>
<section><h2>Windows services</h2>$serviceHtml</section>
<section><h2>Windows Update</h2>$updateHtml</section>
<section><h2>Event log analysis</h2>$eventHtml</section>
<div class="footer">Generated by Windows Health Monitor · Read-only diagnostics</div></main></body></html>
"@
        Set-Content -LiteralPath $htmlPath -Value $html -Encoding utf8
        $paths['Html'] = $htmlPath
    }

    [pscustomobject]@{
        BaseName = $baseName
        OutputDirectory = $resolvedDirectory
        Files = [pscustomobject]$paths
        GeneratedAt = Get-Date
    }
}

Export-ModuleMember -Function New-HealthReport
