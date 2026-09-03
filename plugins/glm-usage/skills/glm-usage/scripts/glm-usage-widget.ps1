# GLM Coding Plan 桌面悬浮窗(Windows PowerShell 5.1+,零依赖)
# 置顶显示,可拖动,每 5 分钟自动刷新;右键菜单:立即刷新 / 开机自启 / 退出
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$scriptPath = Join-Path $env:USERPROFILE '.zcode\scripts\glm-usage.mjs'
$ps1Path    = Join-Path $env:USERPROFILE '.zcode\scripts\glm-usage-widget.ps1'

$xamlText = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="GLM Usage" Topmost="True" WindowStyle="None" AllowsTransparency="True"
        Background="#E6141418" ShowInTaskbar="False" ResizeMode="NoResize"
        Width="342" Height="188" Opacity="0.96">
  <Window.ContextMenu>
    <ContextMenu>
      <MenuItem x:Name="MenuRefresh" Header="立即刷新"/>
      <MenuItem x:Name="MenuStartup" Header="开机自启(点击切换)"/>
      <Separator/>
      <MenuItem x:Name="MenuExit" Header="退出"/>
    </ContextMenu>
  </Window.ContextMenu>
  <StackPanel Margin="14,10">
    <TextBlock x:Name="Title" Foreground="#9AA4B2" FontSize="11" Margin="0,0,0,7"/>
    <TextBlock x:Name="Row5h"   FontSize="13" Margin="0,2" FontFamily="Cascadia Mono,Consolas,Microsoft YaHei UI"/>
    <TextBlock x:Name="RowWeek" FontSize="13" Margin="0,2" FontFamily="Cascadia Mono,Consolas,Microsoft YaHei UI"/>
    <TextBlock x:Name="RowMcp"  FontSize="13" Margin="0,2" FontFamily="Cascadia Mono,Consolas,Microsoft YaHei UI"/>
    <TextBlock x:Name="Row24" Foreground="#9AA4B2" FontSize="11" Margin="0,8,0,0" TextWrapping="Wrap"/>
  </StackPanel>
</Window>
'@

$win = [Windows.Markup.XamlReader]::Parse($xamlText)
$Title   = $win.FindName('Title')
$Row5h   = $win.FindName('Row5h')
$RowWeek = $win.FindName('RowWeek')
$RowMcp  = $win.FindName('RowMcp')
$Row24   = $win.FindName('Row24')

# 初始位置:主屏工作区右上角
$wa = [System.Windows.SystemParameters]::WorkArea
$win.Left = $wa.Right - $win.Width - 16
$win.Top  = $wa.Top + 16

$bc = New-Object System.Windows.Media.BrushConverter
function Brush($hex) { $script:bc.ConvertFromString($hex) }
function RateColor([double]$p) {
  if ($p -ge 80) { '#F14C4C' } elseif ($p -ge 50) { '#E5C07B' } else { '#4EC9B0' }
}
function Add-Run($tb, $text, $color, $size) {
  $r = New-Object System.Windows.Documents.Run($text)
  $r.Foreground = Brush $color
  if ($size) { $r.FontSize = $size }
  $tb.Inlines.Add($r)
}
function Set-Row($tb, $label, $pct, $suffix) {
  $p = [double]$pct
  $filled = [int][Math]::Round($p / 100 * 14)
  $bar = ('▰' * $filled) + ('▱' * (14 - $filled))
  $tb.Inlines.Clear()
  Add-Run $tb ("  {0,-10}" -f $label) '#9AA4B2' $null
  Add-Run $tb "$bar  " (RateColor $p) $null
  Add-Run $tb ("{0,5:F1}%" -f $p) (RateColor $p) $null
  if ($suffix) { Add-Run $tb "  $suffix" '#6B7280' 11 }
}
function Format-Reset($ms) {
  if (-not $ms -or $ms -le 0) { return '' }
  $diff = [DateTimeOffset]::FromUnixTimeMilliseconds($ms) - [DateTimeOffset]::Now
  $t = $diff.ToString('d\.hh\:mm')
  return "{0} 后重置" -f ($t -replace '^0\.', '')
}

function Invoke-Refresh {
  $Title.Text = 'GLM Coding Plan 用量 · 获取中...'
  $Title.Foreground = Brush '#9AA4B2'
  $json = & node $scriptPath --json 2>$null | Out-String
  if (-not $json.Trim()) {
    $Title.Text = 'GLM Coding Plan 用量 · 获取失败(右键立即刷新重试)'
    return
  }
  $d = $json | ConvertFrom-Json
  $q = $d.quota
  foreach ($l in $q.limits) {
    $reset = Format-Reset $l.nextResetTime
    if ($l.type -eq 'TIME_LIMIT') {
      Set-Row $RowMcp 'MCP 本月' $l.percentage ("{0}/{1} 次" -f $l.currentValue, $l.usage)
    } elseif ($l.unit -eq 3) {
      Set-Row $Row5h '5 小时池' $l.percentage $reset
    } elseif ($l.unit -eq 6) {
      Set-Row $RowWeek '每周额度' $l.percentage $reset
    }
  }
  $t = $d.modelUsage.totalUsage
  $tk = [double]$t.totalTokensUsage
  $tkTxt = if ($tk -ge 1e8) { '{0:F2} 亿' -f ($tk / 1e8) } else { '{0:F1} 万' -f ($tk / 1e4) }
  $Row24.Text = "24 小时:{0} 次调用 · {1} tokens" -f $t.totalModelCallCount, $tkTxt
  $Title.Text = "⚡ GLM Coding Plan 用量 · {0} · 更新于 {1}" -f $q.level.ToUpper(), (Get-Date -Format 'HH:mm')
}

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMinutes(5)
$timer.Add_Tick({ Invoke-Refresh })

$win.Add_MouseLeftButtonDown({ $win.DragMove() })

# ContextMenu 内的元素在独立名称域,不能通过 Window.FindName 找,按 Header 索引
$menuItems = @{}
foreach ($mi in $win.ContextMenu.Items) {
  if ($mi -is [System.Windows.Controls.MenuItem]) { $menuItems[$mi.Header] = $mi }
}
$menuItems['立即刷新'].Add_Click({ Invoke-Refresh })
$menuItems['退出'].Add_Click({ $timer.Stop(); $win.Close(); [Environment]::Exit(0) })
$menuItems['开机自启(点击切换)'].Add_Click({
  $vbs = Join-Path ([Environment]::GetFolderPath('Startup')) 'glm-usage-widget.vbs'
  if (Test-Path $vbs) {
    Remove-Item $vbs
    [System.Windows.MessageBox]::Show('已取消开机自启', 'GLM 用量悬浮窗') | Out-Null
  } else {
    $cmd = 'CreateObject("WScript.Shell").Run "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""' + $ps1Path + '""", 0, False'
    [IO.File]::WriteAllText($vbs, $cmd, [Text.Encoding]::ASCII)
    [System.Windows.MessageBox]::Show('已设置开机自启(登录后自动显示)', 'GLM 用量悬浮窗') | Out-Null
  }
})

Invoke-Refresh
$timer.Start()
[void]$win.ShowDialog()
