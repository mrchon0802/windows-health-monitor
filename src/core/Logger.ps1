$script:LoggerPath = $null

function Initialize-Logger {
    param([Parameter(Mandatory)][string]$Path)
    $script:LoggerPath = $Path
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    if (-not (Test-Path $Path)) {
        New-Item -ItemType File -Path $Path -Force | Out-Null
    }
}

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('INFO','WARN','ERROR','DEBUG')][string]$Level,
        [Parameter(Mandatory)][string]$Message
    )
    if (-not $script:LoggerPath) { return }
    $entry = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -LiteralPath $script:LoggerPath -Value $entry -Encoding utf8
}
