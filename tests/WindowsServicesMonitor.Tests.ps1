BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../src/modules/WindowsServicesMonitor.psm1') -Force
}

Describe 'WindowsServicesMonitor module' {
    BeforeEach {
    }

    It 'returns normalized service inventory records' {
        Mock Get-Service {
            @(
                [pscustomobject]@{ Name = 'Dhcp'; DisplayName = 'DHCP Client'; Status = 'Running'; StartType = 'Automatic' }
            )
        } -ModuleName WindowsServicesMonitor

        $result = Get-ServiceInventory

        $result.Count | Should -Be 1
        $result[0].Name | Should -Be 'Dhcp'
        $result[0].StartupType | Should -Be 'Automatic'
    }

    It 'filters inventory by the requested service names' {
        Mock Get-Service {
            @(
                [pscustomobject]@{ Name = 'Dhcp'; DisplayName = 'DHCP Client'; Status = 'Running'; StartType = 'Automatic' }
                [pscustomobject]@{ Name = 'Spooler'; DisplayName = 'Print Spooler'; Status = 'Stopped'; StartType = 'Manual' }
            )
        } -ModuleName WindowsServicesMonitor

        $result = Get-ServiceInventory -ServiceNames 'Spooler'

        $result.Count | Should -Be 1
        $result[0].Name | Should -Be 'Spooler'
    }

    It 'marks a running service as Healthy' {
        $service = [pscustomobject]@{ Name='Dhcp'; DisplayName='DHCP Client'; Status='Running'; StartupType='Automatic' }
        (Get-ServiceHealthAssessment -Services @($service)).Findings[0].Health | Should -Be 'Healthy'
    }

    It 'marks a stopped automatic service as Warning' {
        $service = [pscustomobject]@{ Name='Dhcp'; DisplayName='DHCP Client'; Status='Stopped'; StartupType='Automatic' }
        (Get-ServiceHealthAssessment -Services @($service)).Findings[0].Health | Should -Be 'Warning'
    }

    It 'marks a stopped disabled service as Info' {
        $service = [pscustomobject]@{ Name='Example'; DisplayName='Example Service'; Status='Stopped'; StartupType='Disabled' }
        (Get-ServiceHealthAssessment -Services @($service)).Findings[0].Health | Should -Be 'Info'
    }

    It 'marks a stopped manual service as Info' {
        $service = [pscustomobject]@{ Name='Spooler'; DisplayName='Print Spooler'; Status='Stopped'; StartupType='Manual' }
        (Get-ServiceHealthAssessment -Services @($service)).Findings[0].Health | Should -Be 'Info'
    }

    It 'returns summary counts for the service inventory' {
        $services = @(
            [pscustomobject]@{ Name='Dhcp'; DisplayName='DHCP Client'; Status='Running'; StartupType='Automatic' }
            [pscustomobject]@{ Name='Spooler'; DisplayName='Print Spooler'; Status='Stopped'; StartupType='Automatic' }
        )
        Mock Get-Service {
            @(
                [pscustomobject]@{ Name='Dhcp'; DisplayName='DHCP Client'; Status='Running'; StartType='Automatic' }
                [pscustomobject]@{ Name='Spooler'; DisplayName='Print Spooler'; Status='Stopped'; StartType='Automatic' }
            )
        } -ModuleName WindowsServicesMonitor

        $result = Invoke-ServiceMonitoring

        $result.Assessment.Total | Should -Be 2
        $result.Assessment.Running | Should -Be 1
        $result.Assessment.Stopped | Should -Be 1
        $result.Assessment.Warnings | Should -Be 1
        $result.Assessment.OverallStatus | Should -Be 'Warning'
    }

    It 'throws a useful error when Windows services cannot be queried' {
        Mock Get-Service { throw 'Access denied' } -ModuleName WindowsServicesMonitor

        { Get-ServiceInventory } | Should -Throw '*Unable to retrieve Windows services*'
    }
}
