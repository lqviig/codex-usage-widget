$ErrorActionPreference = 'SilentlyContinue'
$createdNew = $false
$watchMutex = [Threading.Mutex]::new($true, 'Local\CodexUsageWidgetWatcher', [ref]$createdNew)
if (-not $createdNew) { $watchMutex.Dispose(); exit }
$widgetPath = Join-Path $PSScriptRoot 'UsageWidget.ps1'
$wasRunning = $false
try {
 while ($true) {
  $running = @(Get-Process -Name ChatGPT -ErrorAction SilentlyContinue).Count -gt 0
  if ($running -and -not $wasRunning) {
   $arguments = '-NoProfile -ExecutionPolicy Bypass -STA -File "' + $widgetPath + '"'
   Start-Process powershell.exe -ArgumentList $arguments -WindowStyle Hidden
  }
  $wasRunning = $running
  Start-Sleep -Seconds 3
 }
} finally { $watchMutex.ReleaseMutex(); $watchMutex.Dispose() }
