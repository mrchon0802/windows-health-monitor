BeforeAll {
    . "$PSScriptRoot/../src/core/Config.ps1"
}

Describe 'Get-AppSettings' {
    It 'loads required configuration sections' {
        $path = Join-Path $TestDrive 'settings.json'
        '{"thresholds":{},"eventLog":{},"services":{}}' | Set-Content -LiteralPath $path
        $settings = Get-AppSettings -Path $path
        $settings.ContainsKey('thresholds') | Should -BeTrue
        $settings.ContainsKey('eventLog') | Should -BeTrue
        $settings.ContainsKey('services') | Should -BeTrue
    }

    It 'throws when the configuration file is missing' {
        { Get-AppSettings -Path (Join-Path $TestDrive 'missing.json') } | Should -Throw
    }
}
