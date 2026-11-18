# Windows Health Monitor v1.0.0

Initial feature-complete release of Windows Health Monitor.

## Highlights

- Interactive PowerShell 7+ CLI for Windows 10/11.
- System information and CPU, memory, and fixed-disk monitoring.
- Configurable Windows service monitoring.
- Windows Update history and pending-reboot checks.
- System/Application event log analysis with recurring-issue grouping.
- Combined full-system health assessment and troubleshooting recommendations.
- Timestamped HTML, JSON, and CSV report generation.
- Centralized JSON configuration and daily application logging.

## Validation

- Pester 6.2.0
- 46 tests passed
- 0 failed
- Runtime validation completed for the full health check and HTML report generation.

## Run

```powershell
pwsh -ExecutionPolicy Bypass -File .\src\main.ps1
```

## Test

```powershell
Invoke-Pester .\tests -Output Detailed
```

This release performs read-only diagnostics and does not automatically remediate system issues.
