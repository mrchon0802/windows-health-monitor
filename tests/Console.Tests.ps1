BeforeAll {
    . "$PSScriptRoot/../src/core/Console.ps1"
}

Describe 'Read-MenuChoice validation' {
    It 'accepts valid menu options' {
        Mock Read-Host { '6' }
        Read-MenuChoice | Should -Be '6'
    }
}
