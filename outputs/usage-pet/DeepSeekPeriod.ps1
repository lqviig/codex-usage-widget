# Official pricing schedule verified 2026-09-15:
# https://api-docs.deepseek.com/quick_start/pricing/
function Get-DeepSeekPeriod {
 param([DateTimeOffset]$Now = [DateTimeOffset]::UtcNow)
 $utc = $Now.ToUniversalTime()
 $weekday = [int]$utc.DayOfWeek -ge 1 -and [int]$utc.DayOfWeek -le 5
 $hour = $utc.TimeOfDay.TotalHours
 $peak = $weekday -and (($hour -ge 1 -and $hour -lt 4) -or ($hour -ge 6 -and $hour -lt 10))
 [pscustomobject]@{
  Text = if ($peak) { '高峰时段' } else { '空闲时段' }
  Color = if ($peak) { '#FF8585' } else { '#78DDC7' }
 }
}
