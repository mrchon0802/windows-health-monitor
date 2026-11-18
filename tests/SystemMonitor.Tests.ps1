BeforeAll {
    Import-Module "$PSScriptRoot/../src/modules/SystemMonitor.psm1" -Force
}

Describe 'Get-ResourceHealthAssessment' {
    BeforeAll {
        $thresholds = @{
            cpuWarning = 80
            cpuCritical = 95
            memoryWarning = 85
            memoryCritical = 95
            diskFreeWarning = 15
            diskFreeCritical = 5
        }
    }

    It 'returns Healthy when all resource metrics are within thresholds' {
        $cpu = [pscustomobject]@{ Status='OK'; UsagePercent=25 }
        $memory = [pscustomobject]@{ Status='OK'; UsagePercent=50 }
        $disks = @([pscustomobject]@{ Drive='C:'; Status='OK'; FreePercent=40 })

        $result = Get-ResourceHealthAssessment -Cpu $cpu -Memory $memory -Disks $disks -Thresholds $thresholds
        $result.OverallStatus | Should -Be 'Healthy'
    }

    It 'returns Warning when a warning threshold is reached' {
        $cpu = [pscustomobject]@{ Status='OK'; UsagePercent=80 }
        $memory = [pscustomobject]@{ Status='OK'; UsagePercent=50 }
        $disks = @([pscustomobject]@{ Drive='C:'; Status='OK'; FreePercent=40 })

        $result = Get-ResourceHealthAssessment -Cpu $cpu -Memory $memory -Disks $disks -Thresholds $thresholds
        $result.OverallStatus | Should -Be 'Warning'
    }

    It 'returns Critical when a critical threshold is reached' {
        $cpu = [pscustomobject]@{ Status='OK'; UsagePercent=96 }
        $memory = [pscustomobject]@{ Status='OK'; UsagePercent=50 }
        $disks = @([pscustomobject]@{ Drive='C:'; Status='OK'; FreePercent=40 })

        $result = Get-ResourceHealthAssessment -Cpu $cpu -Memory $memory -Disks $disks -Thresholds $thresholds
        $result.OverallStatus | Should -Be 'Critical'
    }

    It 'returns Unknown when required metrics cannot be collected' {
        $cpu = [pscustomobject]@{ Status='Unknown'; UsagePercent=$null }
        $memory = [pscustomobject]@{ Status='OK'; UsagePercent=40 }
        $disks = @()

        $result = Get-ResourceHealthAssessment -Cpu $cpu -Memory $memory -Disks $disks -Thresholds $thresholds
        $result.OverallStatus | Should -Be 'Unknown'
    }
}

Describe 'Get-MemoryUsage' {
    It 'calculates physical memory utilization from CIM values' {
        Mock Get-CimInstance {
            [pscustomobject]@{
                TotalVisibleMemorySize = 16000000
                FreePhysicalMemory = 4000000
            }
        } -ModuleName SystemMonitor -ParameterFilter { $ClassName -eq 'Win32_OperatingSystem' }

        $result = Get-MemoryUsage
        $result.Status | Should -Be 'OK'
        $result.UsagePercent | Should -Be 75
    }
}
