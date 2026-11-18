BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../src/modules/HealthCheck.psm1') -Force
}

Describe 'HealthCheck module - overall assessment' {
    It 'returns Healthy when every component is healthy' {
        $components = @(
            [pscustomobject]@{ Name='Resources'; Status='Healthy'; Details='OK' }
            [pscustomobject]@{ Name='Services'; Status='Healthy'; Details='OK' }
            [pscustomobject]@{ Name='Windows Update'; Status='Healthy'; Details='OK' }
            [pscustomobject]@{ Name='Event Logs'; Status='Healthy'; Details='OK' }
        )
        $result = Get-OverallHealthAssessment -Components $components
        $result.OverallStatus | Should -Be 'Healthy'
        $result.Counts.Healthy | Should -Be 4
        $result.Recommendations.Count | Should -BeGreaterThan 0
    }

    It 'returns Warning when any component has a warning' {
        $components = @(
            [pscustomobject]@{ Name='Resources'; Status='Healthy'; Details='OK' }
            [pscustomobject]@{ Name='Event Logs'; Status='Warning'; Details='Events found' }
        )
        (Get-OverallHealthAssessment -Components $components).OverallStatus | Should -Be 'Warning'
    }

    It 'returns Critical when any component is critical' {
        $components = @(
            [pscustomobject]@{ Name='Resources'; Status='Warning'; Details='High CPU' }
            [pscustomobject]@{ Name='Services'; Status='Critical'; Details='Critical service issue' }
        )
        (Get-OverallHealthAssessment -Components $components).OverallStatus | Should -Be 'Critical'
    }

    It 'returns Warning when known results coexist with an unknown component' {
        $components = @(
            [pscustomobject]@{ Name='Resources'; Status='Healthy'; Details='OK' }
            [pscustomobject]@{ Name='Event Logs'; Status='Unknown'; Details='Access denied' }
        )
        (Get-OverallHealthAssessment -Components $components).OverallStatus | Should -Be 'Warning'
    }

    It 'returns Unknown when no component could be assessed' {
        $components = @(
            [pscustomobject]@{ Name='Resources'; Status='Unknown'; Details='Unavailable' }
            [pscustomobject]@{ Name='Services'; Status='Unknown'; Details='Unavailable' }
        )
        (Get-OverallHealthAssessment -Components $components).OverallStatus | Should -Be 'Unknown'
    }

    It 'returns Unknown for an empty component collection' {
        (Get-OverallHealthAssessment -Components @()).OverallStatus | Should -Be 'Unknown'
    }

    It 'normalizes unsupported component statuses to Unknown' {
        $components = @([pscustomobject]@{ Name='Resources'; Status='Info'; Details='No issue' })
        $result = Get-OverallHealthAssessment -Components $components
        $result.OverallStatus | Should -Be 'Unknown'
        $result.Components[0].Status | Should -Be 'Unknown'
    }

    It 'adds a targeted recommendation for resource warnings' {
        $components = @([pscustomobject]@{ Name='Resources'; Status='Warning'; Details='Disk space low' })
        $result = Get-OverallHealthAssessment -Components $components
        ($result.Recommendations -join ' ') | Should -Match 'resource warnings'
    }
}
