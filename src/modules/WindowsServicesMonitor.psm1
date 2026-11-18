Set-StrictMode -Version Latest

function Get-ServiceInventory {
    [CmdletBinding()]
    param(
        [string[]]$ServiceNames
    )

    try {
        $services = @(Get-Service -ErrorAction Stop)
    }
    catch {
        throw "Unable to retrieve Windows services: $($_.Exception.Message)"
    }

    if ($ServiceNames -and $ServiceNames.Count -gt 0) {
        $services = @($services | Where-Object { $ServiceNames -contains $_.Name })
    }

    foreach ($service in $services) {
        $startType = 'Unknown'
        if ($service.PSObject.Properties['StartType'] -and $null -ne $service.StartType) {
            $startType = [string]$service.StartType
        }

        [pscustomobject]@{
            Name        = [string]$service.Name
            DisplayName = [string]$service.DisplayName
            Status      = [string]$service.Status
            StartupType = $startType
        }
    }
}

function Get-ServiceHealthAssessment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Services
    )

    $findings = foreach ($service in $Services) {
        $status = [string]$service.Status
        $startupType = [string]$service.StartupType

        if ($status -eq 'Running') {
            $health = 'Healthy'
            $message = 'Service is running.'
        }
        elseif ($status -eq 'Stopped' -and $startupType -match '^Automatic') {
            $health = 'Warning'
            $message = 'Automatic-start service is stopped.'
        }
        elseif ($status -eq 'Stopped' -and $startupType -eq 'Disabled') {
            $health = 'Info'
            $message = 'Service is stopped and disabled.'
        }
        elseif ($status -eq 'Stopped') {
            $health = 'Info'
            $message = 'Service is stopped; review whether this is expected.'
        }
        else {
            $health = 'Unknown'
            $message = "Service state is $status."
        }

        [pscustomobject]@{
            Name        = [string]$service.Name
            DisplayName = [string]$service.DisplayName
            Status      = $status
            StartupType = $startupType
            Health      = $health
            Message     = $message
        }
    }

    $findings = @($findings)
    $overallStatus = if ($findings.Health -contains 'Warning') {
        'Warning'
    }
    elseif ($findings.Health -contains 'Unknown') {
        'Unknown'
    }
    elseif ($findings.Health -contains 'Healthy') {
        'Healthy'
    }
    else {
        'Info'
    }

    [pscustomobject]@{
        OverallStatus = $overallStatus
        Total         = $findings.Count
        Running       = @($findings | Where-Object Status -eq 'Running').Count
        Stopped       = @($findings | Where-Object Status -eq 'Stopped').Count
        Warnings      = @($findings | Where-Object Health -eq 'Warning').Count
        Findings      = $findings
    }
}

function Invoke-ServiceMonitoring {
    [CmdletBinding()]
    param(
        [string[]]$ServiceNames
    )

    $services = @(Get-ServiceInventory -ServiceNames $ServiceNames)
    $assessment = Get-ServiceHealthAssessment -Services $services

    [pscustomobject]@{
        CollectedAt = Get-Date
        Services    = $services
        Assessment  = $assessment
    }
}

Export-ModuleMember -Function Get-ServiceInventory, Get-ServiceHealthAssessment, Invoke-ServiceMonitoring
