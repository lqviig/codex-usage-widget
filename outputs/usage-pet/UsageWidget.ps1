param([string]$PreviewPath = '', [switch]$PreviewCollapsed, [switch]$PreviewExit)
$createdNew = $false
$widgetMutex = [Threading.Mutex]::new($true, 'Local\CodexUsageWidget', [ref]$createdNew)
if (-not $createdNew) { $widgetMutex.Dispose(); exit }
$script:toggleEvent = [Threading.EventWaitHandle]::new($false, [Threading.EventResetMode]::ManualReset, 'Local\CodexUsageWidgetToggle')
Add-Type -AssemblyName PresentationFramework
. (Join-Path $PSScriptRoot 'DeepSeekPeriod.ps1')
$ErrorActionPreference = 'Stop'
$python = Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
$stateDir = Join-Path $env:LOCALAPPDATA 'CodexUsageWidget'
[IO.Directory]::CreateDirectory($stateDir) | Out-Null
$configPath = Join-Path $stateDir 'widget.json'
$workerFile = Join-Path $PSScriptRoot 'fetch_usage.py'
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Codex 用量" Width="288" SizeToContent="Height" WindowStyle="None" ResizeMode="NoResize" AllowsTransparency="True" Background="Transparent" Topmost="True" ShowInTaskbar="True" FontFamily="Microsoft YaHei UI">
 <Border x:Name="Root" Background="#F51B2029" BorderBrush="#394352" BorderThickness="1" CornerRadius="18" Padding="18,14">
  <StackPanel>
   <Grid x:Name="Head" Margin="0,0,0,16"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock x:Name="Title" Grid.Column="0" Text="◉  CODEX 用量" Foreground="#EAF0F8" FontWeight="SemiBold" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/><StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Right"><Button x:Name="Toggle" Content="−" Width="26" Background="Transparent" Foreground="#A9B8CC" BorderThickness="0" ToolTip="收成小条 / 展开"/><Button x:Name="Refresh" Content="↻" Width="26" Background="Transparent" Foreground="#A9B8CC" BorderThickness="0" ToolTip="刷新用量"/><Button x:Name="Close" Content="×" Width="26" Background="Transparent" Foreground="#A9B8CC" BorderThickness="0" ToolTip="关闭"/></StackPanel></Grid>
   <StackPanel x:Name="Body">
    <Grid><TextBlock Text="5 小时" Foreground="#BCC8D8"/><TextBlock x:Name="FiveText" Text="—" Foreground="#78DDC7" HorizontalAlignment="Right" FontWeight="Bold"/></Grid>
    <ProgressBar x:Name="FiveBar" Height="5" Margin="0,7,0,5" Maximum="100" Background="#323C4A" Foreground="#78DDC7" BorderThickness="0"/>
    <TextBlock x:Name="FiveReset" Text="正在读取…" Foreground="#8493A8" FontSize="10" Margin="0,0,0,13"/>
    <Grid><TextBlock Text="每周" Foreground="#BCC8D8"/><TextBlock x:Name="WeekText" Text="—" Foreground="#A6B5FF" HorizontalAlignment="Right" FontWeight="Bold"/></Grid>
    <ProgressBar x:Name="WeekBar" Height="5" Margin="0,7,0,5" Maximum="100" Background="#323C4A" Foreground="#A6B5FF" BorderThickness="0"/>
    <TextBlock x:Name="WeekReset" Text="正在读取…" Foreground="#8493A8" FontSize="10"/>
    <Grid Margin="0,12,0,0"><TextBlock x:Name="TokenLabel" Text="Token 用量" Foreground="#BCC8D8"/><TextBlock x:Name="TokenValue" Text="正在读取…" Foreground="#F0CC91" HorizontalAlignment="Right" FontWeight="SemiBold" ToolTip="官方账户统计；不能换算成剩余额度"/></Grid>
    <Border Height="1" Background="#323C4A" Margin="0,14,0,12"/>
    <StackPanel Orientation="Horizontal" Margin="0,0,0,10"><TextBlock Text="◉  DEEPSEEK 今日" Foreground="#EAF0F8" FontWeight="SemiBold" FontSize="11"/><TextBlock x:Name="DsPeriod" Margin="10,0,0,0" FontWeight="SemiBold" FontSize="11" ToolTip="北京时间：周一至周五 09:00–12:00、14:00–18:00 为高峰，其余为空闲。按官方定价时段判断，并非实时服务器负载。"/></StackPanel>
    <Grid><TextBlock Text="消费" Foreground="#BCC8D8"/><TextBlock x:Name="DsCost" Text="正在读取…" Foreground="#FFA9A0" HorizontalAlignment="Right" FontWeight="Bold"/></Grid>
    <Grid Margin="0,8,0,0"><TextBlock Text="Token" Foreground="#BCC8D8"/><TextBlock x:Name="DsTokens" Text="正在读取…" Foreground="#F0CC91" HorizontalAlignment="Right" FontWeight="SemiBold"/></Grid>
    <TextBlock x:Name="DsMeta" Text="" Foreground="#8493A8" FontSize="10" Margin="0,7,0,0"/>
    <TextBlock x:Name="Status" Text="连接本机 Codex · 可拖动" Foreground="#8493A8" FontSize="10" Margin="0,12,0,0"/>
   </StackPanel>
  </StackPanel>
 </Border>
</Window>
'@
$window = [Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($xaml))
$script:preview = [bool]$PreviewPath
$script:shot = $false
$script:workerFile = $workerFile
$script:state = [ordered]@{
 codex = @{ script = 'fetch_usage.py';    output = 'usage.json';    interval = 60;  proc = $null; next = [datetime]::MinValue; started = [datetime]::MinValue; data = $null; stale = $false; error = '' }
 ds    = @{ script = 'fetch_deepseek.py'; output = 'deepseek.json'; interval = 300; proc = $null; next = [datetime]::MinValue; started = [datetime]::MinValue; data = $null; stale = $false; error = '' }
}
$work = [Windows.SystemParameters]::WorkArea
$script:left = $work.Right - 320
$script:top = $work.Bottom - 400
$script:collapsed = $false
if (Test-Path -LiteralPath $configPath) {
 try {
  $saved = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
  if ($null -ne $saved.left) { $script:left = [double]$saved.left }
  if ($null -ne $saved.top) { $script:top = [double]$saved.top }
  if ($saved.collapsed -eq $true) { $script:collapsed = $true }
 } catch { }
}
$window.Left = $script:left
$window.Top = $script:top
function Save-Config {
 if ($script:preview) { return }
 try { [IO.File]::WriteAllText($configPath, ([pscustomobject]@{ left = [int]$window.Left; top = [int]$window.Top; collapsed = [bool]$script:collapsed } | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false)) } catch { }
}
function Update-DeepSeekPeriod {
 $period = Get-DeepSeekPeriod
 $label = $window.FindName('DsPeriod')
 if ($label.Text -ne $period.Text) {
  $label.Text = $period.Text
  $label.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString($period.Color)
 }
}
function Format-Count($value) {
 if ($null -eq $value) { return '暂不可用' }
 if ($value -ge 1000000) { return '{0:0.##}M' -f ($value / 1000000) }
 if ($value -ge 1000) { return '{0:0.##}K' -f ($value / 1000) }
 return [string]$value
}
function Update-Title {
 $title = $window.FindName('Title')
 $codex = $script:state.codex.data
 $ds = $script:state.ds.data
 if (-not $script:collapsed) {
  $title.FontSize = 12
  $title.Text = '◉  CODEX 用量'
  return
 }
 $five = if ($codex -and $null -ne $codex.five.remaining) { '{0:0.#}%' -f $codex.five.remaining } else { '—' }
 $week = if ($codex -and $null -ne $codex.week.remaining) { '{0:0.#}%' -f $codex.week.remaining } else { '—' }
 $cost = if ($ds -and $null -ne $ds.cost) { '¥{0:0.00}' -f [double]$ds.cost } else { '¥—' }
 $title.FontSize = 11
 $title.Text = '◉ 5h ' + $five + ' · 周 ' + $week + ' · ' + $cost
}
function Adjust-Position {
 [Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::Background, [Action]{
  $height = [double]$window.ActualHeight
  if ($height -gt 0) {
   if ($window.Top + $height -gt $work.Bottom) { $window.Top = $work.Bottom - $height }
   if ($window.Top -lt $work.Top) { $window.Top = $work.Top }
  }
  Save-Config
 }) | Out-Null
}
function Set-Collapsed([bool]$flag) {
 $script:collapsed = $flag
 $window.FindName('Toggle').Content = if ($flag) { '+' } else { '−' }
 $window.FindName('Body').Visibility = if ($flag) { 'Collapsed' } else { 'Visible' }
 $window.FindName('Root').Padding = if ($flag) { [Windows.Thickness]::new(18, 8, 18, 8) } else { [Windows.Thickness]::new(18, 14, 18, 14) }
 $window.FindName('Head').Margin = if ($flag) { [Windows.Thickness]::new(0) } else { [Windows.Thickness]::new(0, 0, 0, 16) }
 Update-Title
 Adjust-Position
}
function Start-Fetch([string]$key) {
 $s = $script:state[$key]
 if ($s.proc -and -not $s.proc.HasExited) { return }
 $s.started = Get-Date
 $s.next = (Get-Date).AddSeconds($s.interval)
 try {
  $info = [Diagnostics.ProcessStartInfo]::new()
  $info.FileName = $python
  $info.Arguments = '"' + (Join-Path $PSScriptRoot $s.script) + '" "' + (Join-Path $stateDir $s.output) + '"'
  $info.UseShellExecute = $false
  $info.CreateNoWindow = $true
  $s.proc = [Diagnostics.Process]::Start($info)
 } catch {
  $s.proc = $null
  $s.error = '无法启动读取程序'
 }
}
function Show-Quota($data, $stale) {
 $window.FindName('TokenLabel').Text = if ($data.tokens.label) { $data.tokens.label } else { 'Token 用量' }
 $count = $data.tokens.value
 $window.FindName('TokenValue').Text = Format-Count $count
 $window.FindName('TokenValue').ToolTip = if ($null -eq $count) { '官方接口未返回 Token 数据' } else { ('{0:N0} tokens · 官方账户统计' -f $count) }
 $window.FindName('TokenValue').Opacity = if ($stale) { .4 } else { 1 }
 foreach ($pair in @(@('Five', 'five'), @('Week', 'week'))) {
  $prefix = $pair[0]; $quota = $data.($pair[1])
  $remaining = $quota.remaining
  $window.FindName($prefix+'Text').Text = if ($null -eq $remaining) { '—' } else { ('{0:0.#}% 剩余' -f $remaining) }
  $window.FindName($prefix+'Bar').Value = if ($null -eq $remaining) { 0 } else { $remaining }
  $window.FindName($prefix+'Bar').Opacity = if ($stale) { .4 } else { 1 }
  $reset = '重置时间未知'
  if ($quota.reset) {
   $date = [DateTimeOffset]::FromUnixTimeSeconds([long]$quota.reset).LocalDateTime
   $reset = if ($date -le (Get-Date)) { '重置时间已到 · 等待更新' } else { '重置于 ' + $date.ToString('MM月dd日 HH:mm') }
  }
  $window.FindName($prefix+'Reset').Text = $reset
 }
}
function Show-Data {
 $codex = $script:state.codex
 $ds = $script:state.ds
 if ($codex.data) {
  Show-Quota $codex.data $codex.stale
 } else {
  foreach ($name in @('FiveText', 'WeekText')) { $window.FindName($name).Text = '—' }
  $window.FindName('FiveReset').Text = if ($codex.error) { $codex.error } else { '正在读取…' }
  $window.FindName('WeekReset').Text = if ($codex.error) { $codex.error } else { '正在读取…' }
 }
 $cost = $window.FindName('DsCost')
 $tokens = $window.FindName('DsTokens')
 $meta = $window.FindName('DsMeta')
 if ($ds.data) {
  $cost.Text = '¥{0:0.0000}' -f [double]$ds.data.cost
  $cost.ToolTip = ('{0:N2} {1} · 平台用量接口' -f [double]$ds.data.cost, $ds.data.currency)
  $tokens.Text = Format-Count ([int]$ds.data.tokens)
  $tokens.ToolTip = '{0:N0} tokens · 官方平台统计' -f [int]$ds.data.tokens
  $meta.Text = $ds.data.date + ' · ' + $ds.data.requests + ' 次请求'
 } else {
  $cost.Text = '—'
  $tokens.Text = '—'
  $meta.Text = if ($ds.error) { $ds.error } else { '正在读取…' }
 }
 $cost.Opacity = if ($ds.stale) { .4 } else { 1 }
 $tokens.Opacity = if ($ds.stale) { .4 } else { 1 }
 $failed = @()
 if (-not $codex.data -or $codex.stale) { $failed += 'Codex' }
 if (-not $ds.data -or $ds.stale) { $failed += 'DeepSeek' }
 $stamp = (Get-Date).ToString('HH:mm:ss')
 $window.FindName('Status').Text = if ($failed.Count) { '更新于 ' + $stamp + ' · ' + ($failed -join '/') + ' 未更新' } else { '更新于 ' + $stamp + ' · Codex 60s / DS 5min' }
 Update-Title
}
function Save-Shot {
 $window.UpdateLayout()
 $bitmap = [Windows.Media.Imaging.RenderTargetBitmap]::new([int]$window.ActualWidth, [int]$window.ActualHeight, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
 $bitmap.Render($window)
 $encoder = [Windows.Media.Imaging.PngBitmapEncoder]::new()
 $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
 $stream = [IO.File]::Create($PreviewPath)
 try { $encoder.Save($stream) } finally { $stream.Dispose() }
}
function Invoke-Preview {
 if (-not $script:preview -or $script:shot) { return }
 if (-not ($script:state.codex.data -and $script:state.ds.data)) { return }
 $script:shot = $true
 Save-Shot
 if ($PreviewExit) { $window.Close() }
}
$window.Add_MouseLeftButtonDown({ if ($_.OriginalSource -isnot [Windows.Controls.Button]) { $window.DragMove() } })
$window.Add_MouseLeftButtonUp({ Save-Config })
$window.FindName('Close').Add_Click({ $window.Close() })
$window.FindName('Refresh').Add_Click({ Start-Fetch 'codex'; Start-Fetch 'ds' })
$window.FindName('Toggle').Add_Click({ Set-Collapsed (-not $script:collapsed) })
$timer = [Windows.Threading.DispatcherTimer]::new()
$timer.Interval = [TimeSpan]::FromMilliseconds(400)
$timer.Add_Tick({
 if ($script:toggleEvent.WaitOne(0)) { $window.Close(); return }
 Update-DeepSeekPeriod
 foreach ($key in @('codex', 'ds')) {
  $s = $script:state[$key]
  if ($s.proc -and $s.proc.HasExited) {
   $s.proc.Dispose(); $s.proc = $null
   try {
    $raw = Get-Content -LiteralPath (Join-Path $stateDir $s.output) -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $raw.ok) { throw $(if ($raw.error) { [string]$raw.error } else { '暂不可用' }) }
    if ($raw.at -lt ([DateTimeOffset]$s.started).ToUnixTimeSeconds()) { throw '暂不可用' }
    $s.data = $raw; $s.stale = $false; $s.error = ''
   } catch {
    $s.stale = $true
    if (-not $s.data) { $s.error = $_.Exception.Message }
   }
   Show-Data
   Invoke-Preview
  }
  if ((Get-Date) -ge $s.next) { Start-Fetch $key }
 }
})
$window.Add_Closed({ $timer.Stop(); Save-Config; $script:toggleEvent.Dispose() })
$window.Add_ContentRendered({
 Update-DeepSeekPeriod
 if ($PreviewCollapsed) { Set-Collapsed $true } else { Set-Collapsed $script:collapsed }
 Start-Fetch 'codex'
 Start-Fetch 'ds'
 $timer.Start()
})
$window.ShowDialog() | Out-Null
$widgetMutex.ReleaseMutex()
$widgetMutex.Dispose()
