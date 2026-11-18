function Get-AppSettings {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Configuration file not found: $Path"
    }

    try {
        $settings = Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
    }
    catch {
        throw "Unable to read configuration file '$Path': $($_.Exception.Message)"
    }

    $requiredSections = @('thresholds', 'eventLog', 'services')
    foreach ($section in $requiredSections) {
        if (-not $settings.ContainsKey($section)) {
            throw "Configuration is missing required section: $section"
        }
    }

    return $settings
}
