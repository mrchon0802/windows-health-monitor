function Clear-Console { Clear-Host }

function Show-Banner {
    Write-Host ''
    Write-Host ' __        ___           _                 ' -ForegroundColor Cyan
    Write-Host ' \ \      / (_)_ __   __| | _____      __  ' -ForegroundColor Cyan
    Write-Host '  \ \ /\ / /| |  _ \ / _` |/ _ \ \ /\ / /  ' -ForegroundColor Cyan
    Write-Host '   \ V  V / | | | | | (_| |  __/\ V  V /   ' -ForegroundColor Cyan
    Write-Host '    \_/\_/  |_|_| |_|\__,_|\___| \_/\_/    ' -ForegroundColor Cyan
    Write-Host ''
    Write-Host ' WINDOWS HEALTH MONITOR' -ForegroundColor White
    Write-Host ' System Troubleshooting & Health Assessment' -ForegroundColor DarkGray
    Write-Host (" Version 1.0.0  |  PowerShell {0}" -f $PSVersionTable.PSVersion) -ForegroundColor DarkGray
    Write-Host ''
}

function Write-Section {
    param([Parameter(Mandatory)][string]$Title)
    Write-Host ('=' * 62) -ForegroundColor DarkCyan
    Write-Host ("  {0}" -f $Title) -ForegroundColor Cyan
    Write-Host ('=' * 62) -ForegroundColor DarkCyan
}

function Read-MenuChoice {
    do {
        $choice = (Read-Host 'Select an option').Trim()
        if ($choice -match '^(0|[1-8])$') { return $choice }
        Write-Host 'Invalid input. Enter a number from 0 to 8.' -ForegroundColor Red
    } while ($true)
}

function Read-EnterToContinue { [void](Read-Host 'Press Enter to return to the main menu') }

function Show-MainMenu {
    Write-Host ' MAIN MENU' -ForegroundColor Green
    Write-Host ''
    Write-Host ' [1] System Information'
    Write-Host ' [2] Resource Monitoring'
    Write-Host ' [3] Windows Services'
    Write-Host ' [4] Windows Update'
    Write-Host ' [5] Event Log Analysis'
    Write-Host ' [6] Full System Health Check'
    Write-Host ' [7] Generate / View Report'
    Write-Host ' [8] Settings'
    Write-Host ' [0] Exit'
    Write-Host ''
}
