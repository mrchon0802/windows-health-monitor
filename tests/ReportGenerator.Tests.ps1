BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../src/modules/ReportGenerator.psm1') -Force
}

Describe 'ReportGenerator module' {
    BeforeEach {
        $script:tempDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
        $script:sampleResult = [pscustomobject]@{
            CollectedAt = Get-Date
            Resource = $null
            Services = $null
            WindowsUpdate = $null
            EventLogs = $null
            Assessment = [pscustomobject]@{
                OverallStatus = 'Warning'
                Components = @(
                    [pscustomobject]@{ Name='Resources'; Status='Warning'; Details='CPU 82%' },
                    [pscustomobject]@{ Name='Services'; Status='Healthy'; Details='6 total' }
                )
                Counts = [pscustomobject]@{ Healthy=1; Warning=1; Critical=0; Unknown=0 }
                Recommendations = @('Review resource warnings.')
            }
        }
    }

    It 'creates HTML, JSON and CSV report files by default' {
        $result = New-HealthReport -HealthCheckResult $script:sampleResult -OutputDirectory $script:tempDirectory
        Test-Path $result.Files.Html | Should -BeTrue
        Test-Path $result.Files.Json | Should -BeTrue
        Test-Path $result.Files.Csv | Should -BeTrue
    }

    It 'includes the overall status and recommendations in HTML' {
        $result = New-HealthReport -HealthCheckResult $script:sampleResult -OutputDirectory $script:tempDirectory -Formats html
        $html = Get-Content -LiteralPath $result.Files.Html -Raw
        $html | Should -Match 'System Health Report'
        $html | Should -Match 'WARNING'
        $html | Should -Match 'Review resource warnings\.'
    }

    It 'escapes HTML-sensitive text in report values' {
        $script:sampleResult.Assessment.Components[0].Details = '<script>alert(1)</script>'
        $result = New-HealthReport -HealthCheckResult $script:sampleResult -OutputDirectory $script:tempDirectory -Formats html
        $html = Get-Content -LiteralPath $result.Files.Html -Raw
        $html | Should -Not -Match '<script>alert'
        $html | Should -Match '&lt;script&gt;'
    }

    It 'exports component rows to CSV' {
        $result = New-HealthReport -HealthCheckResult $script:sampleResult -OutputDirectory $script:tempDirectory -Formats csv
        $rows = Import-Csv -LiteralPath $result.Files.Csv
        $rows.Count | Should -Be 2
        $rows[0].Name | Should -Be 'Resources'
    }

    It 'supports selecting a single output format' {
        $result = New-HealthReport -HealthCheckResult $script:sampleResult -OutputDirectory $script:tempDirectory -Formats json
        Test-Path $result.Files.Json | Should -BeTrue
        $result.Files.Html | Should -BeNullOrEmpty
        $result.Files.Csv | Should -BeNullOrEmpty
    }

    AfterEach {
        if (Test-Path $script:tempDirectory) { Remove-Item $script:tempDirectory -Recurse -Force }
    }
}
