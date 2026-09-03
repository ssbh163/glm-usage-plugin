# GLM Coding Plan 桌面悬浮窗(Windows PowerShell 5.1+,零依赖)
# 置顶显示,可拖动,每 5 分钟自动刷新;右键菜单:立即刷新 / 开机自启 / 退出
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type -Namespace GLMNative -Name Hotkey -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
[DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
'@

# 单实例保护:已有实例时,先让已运行的窗口显示出来,再退出本进程
$mutex = New-Object System.Threading.Mutex($false, 'Global\GLM-Usage-Widget')
$ownsMutex = $false
try { $ownsMutex = $mutex.WaitOne(0) } catch { $ownsMutex = $true }  # 前实例残留(AbandonedMutex),接管
if (-not $ownsMutex) {
  try {
    [System.Threading.EventWaitHandle]::OpenExisting('Global\GLM-Usage-Widget-Show').Set() | Out-Null
  } catch { }
  exit
}

$scriptPath = Join-Path $env:USERPROFILE '.zcode\scripts\glm-usage.mjs'
# 若未 --install 过,退回到插件缓存中的脚本(取最高版本)
if (-not (Test-Path $scriptPath)) {
  $cached = Get-ChildItem "$env:USERPROFILE\.zcode\cli\plugins\cache\*\glm-usage\*\skills\glm-usage\scripts\glm-usage.mjs" |
    Sort-Object FullName -Descending | Select-Object -First 1
  if ($cached) { $scriptPath = $cached.FullName }
}
$ps1Path    = Join-Path $env:USERPROFILE '.zcode\scripts\glm-usage-widget.ps1'

$xamlText = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="GLM Usage" Topmost="True" WindowStyle="None" AllowsTransparency="True"
        Background="#E6141418" ShowInTaskbar="False" ResizeMode="NoResize" ShowActivated="False"
        Width="342" Height="208" Opacity="0.96">
  <Window.ContextMenu>
    <ContextMenu>
      <MenuItem x:Name="MenuRefresh" Header="立即刷新"/>
      <MenuItem x:Name="MenuStartup" Header="开机自启(点击切换)"/>
      <Separator/>
      <MenuItem x:Name="MenuExit" Header="退出"/>
    </ContextMenu>
  </Window.ContextMenu>
  <Grid>
    <TextBlock x:Name="CloseBtn" Text="✕" FontSize="14" FontWeight="Bold" Foreground="#B7C0CD"
               HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,8,10,0"
               Cursor="Hand" ToolTip="隐藏悬浮窗(Ctrl+G 或启动 ZCode 时唤回;右键菜单可彻底退出)"/>
    <StackPanel Margin="14,10,24,10">
      <TextBlock x:Name="Title" Foreground="#9AA4B2" FontSize="11" Margin="0,0,0,7"/>
      <TextBlock x:Name="Row5h"   FontSize="13" Margin="0,2" FontFamily="Cascadia Mono,Consolas,Microsoft YaHei UI"/>
      <TextBlock x:Name="RowWeek" FontSize="13" Margin="0,2" FontFamily="Cascadia Mono,Consolas,Microsoft YaHei UI"/>
      <TextBlock x:Name="RowMcp"  FontSize="13" Margin="0,2" FontFamily="Cascadia Mono,Consolas,Microsoft YaHei UI"/>
      <TextBlock x:Name="Row24" Foreground="#9AA4B2" FontSize="11" Margin="0,8,0,0" TextWrapping="Wrap"/>
    </StackPanel>
  </Grid>
</Window>
'@

$win = [Windows.Markup.XamlReader]::Parse($xamlText)
$Title   = $win.FindName('Title')
$Row5h   = $win.FindName('Row5h')
$RowWeek = $win.FindName('RowWeek')
$RowMcp  = $win.FindName('RowMcp')
$Row24   = $win.FindName('Row24')
$CloseBtn = $win.FindName('CloseBtn')

# 初始位置:默认主屏右上角;若有保存的位置且仍在当前屏幕范围内则恢复
$posFile = Join-Path $env:USERPROFILE '.zcode\scripts\glm-usage-widget.pos.json'
$wa = [System.Windows.SystemParameters]::WorkArea
$win.Left = $wa.Right - $win.Width - 16
$win.Top  = $wa.Top + 16
if (Test-Path $posFile) {
  try {
    $pos = Get-Content $posFile -Raw | ConvertFrom-Json
    if ($pos.Left -is [double] -and $pos.Top -is [double] -and
        $pos.Left -ge ($wa.Left - 20) -and ($pos.Left + $win.Width) -le ($wa.Right + 20) -and
        $pos.Top -ge ($wa.Top - 20) -and ($pos.Top + $win.Height) -le ($wa.Bottom + 20)) {
      $win.Left = $pos.Left
      $win.Top = $pos.Top
    }
  } catch { }
}
function Save-Pos {
  try {
    @{ Left = $win.Left; Top = $win.Top } | ConvertTo-Json | Set-Content -Path $posFile -Encoding ASCII
  } catch { }
}

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
function PadW([string]$s, [int]$w) {
  $len = 0
  foreach ($ch in $s.ToCharArray()) { if ([int]$ch -gt 127) { $len += 2 } else { $len += 1 } }
  return $s + (' ' * [Math]::Max(0, $w - $len))
}
function Set-Row($tb, $label, $pct, $subline) {
  $p = [double]$pct
  $filled = [int][Math]::Round($p / 100 * 14)
  $bar = ('▰' * $filled) + ('▱' * (14 - $filled))
  $tb.Inlines.Clear()
  Add-Run $tb ('  ' + (PadW $label 10)) '#C0C8D4' $null
  Add-Run $tb "$bar  " (RateColor $p) $null
  Add-Run $tb ("{0,5:F1}%" -f $p) (RateColor $p) $null
  if ($subline) {
    $tb.Inlines.Add((New-Object System.Windows.Documents.LineBreak))
    Add-Run $tb "      $subline" '#6B7280' 11
  }
}
function Format-Clock($ms) {
  if (-not $ms -or $ms -le 0) { return '' }
  [DateTimeOffset]::FromUnixTimeMilliseconds($ms).LocalDateTime.ToString('MM/dd HH:mm')
}
function Format-Reset($ms) {
  if (-not $ms -or $ms -le 0) { return '' }
  $span = [DateTimeOffset]::FromUnixTimeMilliseconds($ms) - [DateTimeOffset]::Now
  $parts = @()
  if ($span.Days) { $parts += ("{0} 天" -f $span.Days) }
  if ($span.Hours) { $parts += ("{0} 小时" -f $span.Hours) }
  if ($span.Minutes -or ($span.Days -eq 0 -and $span.Hours -eq 0)) { $parts += ("{0} 分钟" -f $span.Minutes) }
  return ($parts -join ' ') + '后'
}

function Invoke-Refresh {
  $Title.Text = 'GLM Coding Plan 用量 · 获取中...'
  $Title.Foreground = Brush '#9AA4B2'
  $raw = (& node $scriptPath --json 2>&1 | Out-String).Trim()
  $d = $null
  if ($raw) { try { $d = $raw | ConvertFrom-Json } catch { $d = $null } }
  if (-not $d -or -not $d.quota) {
    if ($raw -match '401') {
      $Title.Text = '⚡ API Key 已失效或被更换 · 请在 ZCode 设置中更新,修复后自动恢复'
    } elseif ($raw) {
      $Title.Text = '⚡ 获取失败:' + (($raw -split "`r?`n")[0])
    } else {
      $Title.Text = '⚡ 获取失败(右键可立即重试)'
    }
    return
  }
  $q = $d.quota
  foreach ($l in $q.limits) {
    if ($l.type -eq 'TIME_LIMIT') {
      Set-Row $RowMcp 'MCP 本月' $l.percentage ("已用 {0}/{1} 次 · 剩余 {2}" -f $l.currentValue, $l.usage, $l.remaining)
    } elseif ($l.unit -eq 3) {
      Set-Row $Row5h '5 小时池' $l.percentage ("↻ {0} · {1}重置" -f (Format-Clock $l.nextResetTime), (Format-Reset $l.nextResetTime))
    } elseif ($l.unit -eq 6) {
      Set-Row $RowWeek '每周额度' $l.percentage ("↻ {0} · {1}重置" -f (Format-Clock $l.nextResetTime), (Format-Reset $l.nextResetTime))
    }
  }
  $t = $d.modelUsage.totalUsage
  $tk = [double]$t.totalTokensUsage
  $tkTxt = if ($tk -ge 1e8) { '{0:F2} 亿' -f ($tk / 1e8) } else { '{0:F1} 万' -f ($tk / 1e4) }
  $Row24.Text = "24 小时:{0} 次调用 · {1} tokens" -f $t.totalModelCallCount, $tkTxt
  $Title.Text = "⚡ GLM Coding Plan 用量 · {0} · 更新于 {1}" -f $q.level.ToUpper(), (Get-Date -Format 'HH:mm')
}

# 自动刷新间隔(分钟),按需调整
$refreshMinutes = 10
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMinutes($refreshMinutes)
$timer.Add_Tick({ Invoke-Refresh })

$win.Add_MouseLeftButtonDown({
  if ($_.OriginalSource -ne $CloseBtn) { $win.DragMove(); Save-Pos }
})
$win.Add_Closing({ Save-Pos })

# 左上角 ✕ 关闭按钮:悬停变红,点击隐藏(进程驻留,Ctrl+Alt+U 唤回)
$CloseBtn.Add_MouseEnter({ $CloseBtn.Foreground = Brush '#F14C4C' })
$CloseBtn.Add_MouseLeave({ $CloseBtn.Foreground = Brush '#B7C0CD' })
$CloseBtn.Add_MouseLeftButtonUp({ $win.Hide() })

# ContextMenu 内的元素在独立名称域,不能通过 Window.FindName 找,按 Header 索引
$menuItems = @{}
foreach ($mi in $win.ContextMenu.Items) {
  if ($mi -is [System.Windows.Controls.MenuItem]) { $menuItems[$mi.Header] = $mi }
}
$menuItems['立即刷新'].Add_Click({ Invoke-Refresh })
$menuItems['退出'].Add_Click({
  try { if ($script:helper) { [GLMNative.Hotkey]::UnregisterHotKey($script:helper.Handle, 0xB001) | Out-Null } } catch { }
  $timer.Stop(); $win.Close(); [Environment]::Exit(0)
})
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

# 全局快捷键(可改):0x2=Ctrl,0x1=Alt,0x4=Shift 可组合;G=0x47
$hotkeyModifiers = 0x2
$hotkeyKey = 0x47
$script:helper = $null
$win.Add_SourceInitialized({
  $script:helper = New-Object System.Windows.Interop.WindowInteropHelper($win)
  [void][GLMNative.Hotkey]::RegisterHotKey($script:helper.Handle, 0xB001, $script:hotkeyModifiers, $script:hotkeyKey)
  $src = [System.Windows.Interop.HwndSource]::FromHwnd($script:helper.Handle)
  $src.AddHook({
    param($hwnd, $msg, $wParam, $lParam, [ref]$handled)
    if ($msg -eq 0x0312 -and $wParam.ToInt64() -eq 0xB001) {
      if ($win.IsVisible) { $win.Hide() } else { $win.Show() }
      $handled.Value = $true
    }
    [IntPtr]::Zero
  })
})

# ZCode 启动检测:出现新的 ZCode 进程 = 一次真正的启动(后台已运行时打开窗口不产生新进程,不算)
# 检测到启动时把悬浮窗唤起到前台
$zcodeSeen = @{}
foreach ($p in (Get-Process -Name 'ZCode' -ErrorAction SilentlyContinue)) { $zcodeSeen[$p.Id] = $true }
$zcodeTimer = New-Object System.Windows.Threading.DispatcherTimer
$zcodeTimer.Interval = [TimeSpan]::FromMilliseconds(2000)
$zcodeTimer.Add_Tick({
  $alive = @{}
  foreach ($p in (Get-Process -Name 'ZCode' -ErrorAction SilentlyContinue)) {
    $alive[$p.Id] = $true
    if (-not $zcodeSeen.ContainsKey($p.Id)) {
      if (-not $win.IsVisible) { $win.Show() }
      $win.Activate()
    }
  }
  $zcodeSeen = $alive
})
$zcodeTimer.Start()

# 已有实例被再次"启动"时(如双击桌面图标),通过命名事件把窗口调到前台。
# 注意:不能用 ThreadPool 回调(无 runspace 的线程上运行 scriptblock 会崩进程),
# 这里用 UI 线程上的高频 DispatcherTimer 轮询事件。
$showEvt = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, 'Global\GLM-Usage-Widget-Show')
$wakeTimer = New-Object System.Windows.Threading.DispatcherTimer
$wakeTimer.Interval = [TimeSpan]::FromMilliseconds(250)
$wakeTimer.Add_Tick({
  if ($showEvt.WaitOne(0)) {
    if (-not $win.IsVisible) { $win.Show() } else { $win.Activate() }
  }
})
$wakeTimer.Start()

Invoke-Refresh
$timer.Start()
# 非模态显示 + 手动跑消息循环:Hide() 不会结束进程,可被热键/事件再次唤起
$win.Show()
[System.Windows.Threading.Dispatcher]::Run()
