Set-StrictMode -Version Latest

function Get-SystemInformation {
    [CmdletBinding()]
    param()

    try {
        $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $processor = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop |
            Select-Object -First 1

        $bootTime = $os.LastBootUpTime
        if ($bootTime -isnot [datetime]) {
            $bootTime = [Management.ManagementDateTimeConverter]::ToDateTime([string]$bootTime)
        }

        [pscustomobject]@{
            ComputerName = $env:COMPUTERNAME
            Manufacturer = $computer.Manufacturer
            Model = $computer.Model
            OperatingSystem = $os.Caption
            OSVersion = $os.Version
            BuildNumber = $os.BuildNumber
            Architecture = $os.OSArchitecture
            ProcessorName = $processor.Name
            LogicalProcessors = $computer.NumberOfLogicalProcessors
            TotalPhysicalMemoryGB = [math]::Round(($computer.TotalPhysicalMemory / 1GB), 2)
            LastBootTime = $bootTime
            Uptime = (Get-Date) - $bootTime
            CollectedAt = Get-Date
            Status = 'OK'
            ErrorMessage = $null
        }
    }
    catch {
        throw "Unable to collect system information: $($_.Exception.Message)"
    }
}

function Get-CpuUsage {
    [CmdletBinding()]
    param(
        [ValidateRange(1, 10)]
        [int]$SampleCount = 2,
        [ValidateRange(1, 10)]
        [int]$SampleIntervalSeconds = 1
    )

    try {
        # Win32_PerfFormattedData provides a point-in-time percentage and avoids
        # localized Performance Counter path names.
        $cpu = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Processor -ErrorAction Stop |
            Where-Object { $_.Name -eq '_Total' } |
            Select-Object -First 1

        if ($null -eq $cpu) {
            throw 'The aggregate CPU performance data (_Total) was not available.'
        }

        $usage = [double]$cpu.PercentProcessorTime
        [pscustomobject]@{
            UsagePercent = [math]::Round([math]::Min(100, [math]::Max(0, $usage)), 2)
            SampledAt = Get-Date
            Source = 'Win32_PerfFormattedData_PerfOS_Processor'
            Status = 'OK'
            ErrorMessage = $null
        }
    }
    catch {
        [pscustomobject]@{
            UsagePercent = $null
            SampledAt = Get-Date
            Source = 'Win32_PerfFormattedData_PerfOS_Processor'
            Status = 'Unknown'
            ErrorMessage = $_.Exception.Message
        }
    }
}

function Get-MemoryUsage {
    [CmdletBinding()]
    param()

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $totalKB = [double]$os.TotalVisibleMemorySize
        $freeKB = [double]$os.FreePhysicalMemory

        if ($totalKB -le 0 -or $freeKB -lt 0 -or $freeKB -gt $totalKB) {
            throw 'The operating system returned invalid physical memory values.'
        }

        $usedKB = $totalKB - $freeKB
        [pscustomobject]@{
            TotalGB = [math]::Round(($totalKB / 1MB), 2)
            UsedGB = [math]::Round(($usedKB / 1MB), 2)
            AvailableGB = [math]::Round(($freeKB / 1MB), 2)
            UsagePercent = [math]::Round(($usedKB / $totalKB) * 100, 2)
            CollectedAt = Get-Date
            Status = 'OK'
            ErrorMessage = $null
        }
    }
    catch {
        [pscustomobject]@{
            TotalGB = $null
            UsedGB = $null
            AvailableGB = $null
            UsagePercent = $null
            CollectedAt = Get-Date
            Status = 'Unknown'
            ErrorMessage = $_.Exception.Message
        }
    }
}

function Get-DiskUsage {
    [CmdletBinding()]
    param(
        [string[]]$DriveLetters
    )

    try {
        $volumes = Get-Volume -ErrorAction Stop |
            Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' }

        if ($DriveLetters) {
            $wanted = $DriveLetters | ForEach-Object { $_.TrimEnd(':').ToUpperInvariant() }
            $volumes = $volumes | Where-Object { $wanted -contains ([string]$_.DriveLetter).ToUpperInvariant() }
        }

        @($volumes | ForEach-Object {
            $size = [double]$_.Size
            $free = [double]$_.SizeRemaining
            if ($size -le 0 -or $free -lt 0 -or $free -gt $size) {
                [pscustomobject]@{
                    Drive = "$($_.DriveLetter):"; FileSystem = $_.FileSystem
                    SizeGB = $null; UsedGB = $null; FreeGB = $null
                    FreePercent = $null; Status = 'Unknown'
                    ErrorMessage = 'Invalid volume size information.'
                }
            }
            else {
                [pscustomobject]@{
                    Drive = "$($_.DriveLetter):"
                    FileSystem = $_.FileSystem
                    SizeGB = [math]::Round(($size / 1GB), 2)
                    UsedGB = [math]::Round((($size - $free) / 1GB), 2)
                    FreeGB = [math]::Round(($free / 1GB), 2)
                    FreePercent = [math]::Round(($free / $size) * 100, 2)
                    Status = 'OK'
                    ErrorMessage = $null
                }
            }
        })
    }
    catch {
        [pscustomobject]@{
            Drive = $null; FileSystem = $null; SizeGB = $null
            UsedGB = $null; FreeGB = $null; FreePercent = $null
            Status = 'Unknown'; ErrorMessage = $_.Exception.Message
        }
    }
}

function Get-ResourceHealthAssessment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()][object]$Cpu,
        [Parameter(Mandatory)][AllowNull()][object]$Memory,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Disks,
        [Parameter(Mandatory)][hashtable]$Thresholds
    )

    $findings = [System.Collections.Generic.List[object]]::new()

    if ($null -eq $Cpu -or $Cpu.Status -ne 'OK' -or $null -eq $Cpu.UsagePercent) {
        $findings.Add([pscustomobject]@{ Component='CPU'; Status='Unknown'; Message='CPU usage could not be collected.' })
    }
    elseif ($Cpu.UsagePercent -ge $Thresholds.cpuCritical) {
        $findings.Add([pscustomobject]@{ Component='CPU'; Status='Critical'; Message="CPU usage is $($Cpu.UsagePercent)%." })
    }
    elseif ($Cpu.UsagePercent -ge $Thresholds.cpuWarning) {
        $findings.Add([pscustomobject]@{ Component='CPU'; Status='Warning'; Message="CPU usage is $($Cpu.UsagePercent)%." })
    }
    else {
        $findings.Add([pscustomobject]@{ Component='CPU'; Status='Healthy'; Message="CPU usage is $($Cpu.UsagePercent)%." })
    }

    if ($null -eq $Memory -or $Memory.Status -ne 'OK' -or $null -eq $Memory.UsagePercent) {
        $findings.Add([pscustomobject]@{ Component='Memory'; Status='Unknown'; Message='Memory usage could not be collected.' })
    }
    elseif ($Memory.UsagePercent -ge $Thresholds.memoryCritical) {
        $findings.Add([pscustomobject]@{ Component='Memory'; Status='Critical'; Message="Memory usage is $($Memory.UsagePercent)%." })
    }
    elseif ($Memory.UsagePercent -ge $Thresholds.memoryWarning) {
        $findings.Add([pscustomobject]@{ Component='Memory'; Status='Warning'; Message="Memory usage is $($Memory.UsagePercent)%." })
    }
    else {
        $findings.Add([pscustomobject]@{ Component='Memory'; Status='Healthy'; Message="Memory usage is $($Memory.UsagePercent)%." })
    }

    foreach ($disk in $Disks) {
        if ($disk.Status -ne 'OK' -or $null -eq $disk.FreePercent) {
            $findings.Add([pscustomobject]@{ Component="Disk $($disk.Drive)"; Status='Unknown'; Message='Disk capacity could not be collected.' })
        }
        elseif ($disk.FreePercent -le $Thresholds.diskFreeCritical) {
            $findings.Add([pscustomobject]@{ Component="Disk $($disk.Drive)"; Status='Critical'; Message="Only $($disk.FreePercent)% free space remains." })
        }
        elseif ($disk.FreePercent -le $Thresholds.diskFreeWarning) {
            $findings.Add([pscustomobject]@{ Component="Disk $($disk.Drive)"; Status='Warning'; Message="Only $($disk.FreePercent)% free space remains." })
        }
        else {
            $findings.Add([pscustomobject]@{ Component="Disk $($disk.Drive)"; Status='Healthy'; Message="$($disk.FreePercent)% free space remains." })
        }
    }

    if ($findings.Count -eq 0) {
        $overall = 'Unknown'
    }
    elseif ($findings.Status -contains 'Critical') {
        $overall = 'Critical'
    }
    elseif ($findings.Status -contains 'Warning') {
        $overall = 'Warning'
    }
    elseif ($findings.Status -contains 'Unknown') {
        $overall = 'Unknown'
    }
    else {
        $overall = 'Healthy'
    }

    [pscustomobject]@{
        OverallStatus = $overall
        Findings = @($findings)
        AssessedAt = Get-Date
    }
}

function Invoke-ResourceMonitoring {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Thresholds)

    $cpu = Get-CpuUsage
    $memory = Get-MemoryUsage
    $disks = @(Get-DiskUsage)
    $assessment = Get-ResourceHealthAssessment -Cpu $cpu -Memory $memory -Disks $disks -Thresholds $Thresholds

    [pscustomobject]@{
        Cpu = $cpu
        Memory = $memory
        Disks = $disks
        Assessment = $assessment
        CollectedAt = Get-Date
    }
}

Export-ModuleMember -Function Get-SystemInformation, Get-CpuUsage, Get-MemoryUsage, Get-DiskUsage, Get-ResourceHealthAssessment, Invoke-ResourceMonitoring
