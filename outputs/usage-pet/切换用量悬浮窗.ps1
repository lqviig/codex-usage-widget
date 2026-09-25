$ErrorActionPreference = 'Stop'
$widgetName = 'Local\CodexUsageWidget'
$eventName = 'Local\CodexUsageWidgetToggle'
$isRunning = $false
try {
 $mutex = [Threading.Mutex]::OpenExisting($widgetName)
 try {
  $isRunning = -not $mutex.WaitOne(0)
  if (-not $isRunning) { $mutex.ReleaseMutex() }
 } finally { $mutex.Dispose() }
} catch [Threading.WaitHandleCannotBeOpenedException] {
 $isRunning = $false
}
if ($isRunning) {
 try {
  $toggle = [Threading.EventWaitHandle]::new($false, [Threading.EventResetMode]::ManualReset, $eventName)
  $toggle.Set() | Out-Null
  $toggle.Dispose()
 } catch {
  [Windows.Forms.MessageBox]::Show('暂时无法关闭悬浮窗，请稍后再试。', '用量悬浮窗') | Out-Null
 }
 exit
}
$widgetPath = Join-Path $PSScriptRoot 'UsageWidget.ps1'
$arguments = '-NoProfile -ExecutionPolicy Bypass -STA -File "' + $widgetPath + '"'
Start-Process -FilePath (Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe') -ArgumentList $arguments -WindowStyle Hidden
