# GLM Coding Plan 桌面悬浮窗(Windows PowerShell 5.1+,零依赖)
# 深色圆角卡片 UI(对齐 macOS GLMUsageHUD 视觉规格)
# 生命周期与插件绑定:由插件 SessionStart hook 拉起,插件卸载(本脚本被删)后自动退出
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type -Namespace GLMNative -Name Hotkey -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
[DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
'@

# 单实例保护:已有实例时,手动启动会唤起已有窗口;-NoShowIfExists 启动(插件 hook 每会话拉起)则静默退出
$mutex = New-Object System.Threading.Mutex($false, 'Global\GLM-Usage-Widget')
$ownsMutex = $false
try { $ownsMutex = $mutex.WaitOne(0) } catch { $ownsMutex = $true }  # 前实例残留(AbandonedMutex),接管
if (-not $ownsMutex) {
  if ($args -notcontains 'NoShowIfExists') {
    try {
      [System.Threading.EventWaitHandle]::OpenExisting('Global\GLM-Usage-Widget-Show').Set() | Out-Null
    } catch { }
  }
  exit
}

$scriptPath = Join-Path $env:USERPROFILE '.zcode\scripts\glm-usage.mjs'
# 若未 --install 过,退回到插件缓存中的脚本(取最高版本)
if (-not (Test-Path $scriptPath)) {
  $cached = Get-ChildItem "$env:USERPROFILE\.zcode\cli\plugins\cache\*\glm-usage\*\skills\glm-usage\scripts\glm-usage.mjs" |
    Sort-Object FullName -Descending | Select-Object -First 1
  if ($cached) { $scriptPath = $cached.FullName }
}

$xamlText = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="GLM Usage" Topmost="True" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" ShowInTaskbar="False" ResizeMode="NoResize" ShowActivated="False"
        Width="415" SizeToContent="Height">
  <Window.ContextMenu>
    <ContextMenu>
      <MenuItem x:Name="MenuRefresh" Header="立即刷新"/>
      <Separator/>
      <MenuItem x:Name="MenuExit" Header="退出"/>
    </ContextMenu>
  </Window.ContextMenu>
  <Border CornerRadius="16" Background="#F01C1F24" BorderBrush="#1AFFFFFF" BorderThickness="1"
          Margin="10" Padding="20,14">
    <StackPanel>
      <!-- 标题栏 -->
      <Grid>
        <TextBlock Text="⚡ GLM Coding Plan" FontSize="16" FontWeight="Bold" Foreground="#F5F6F8"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
          <TextBlock x:Name="BtnRefresh" Text="↻" FontSize="15" Foreground="#99A0AA" Cursor="Hand"
                     ToolTip="立即刷新" Margin="0,0,16,0"/>
          <TextBlock x:Name="BtnClose" Text="✕" FontSize="15" FontWeight="Bold" Foreground="#99A0AA"
                     Cursor="Hand" ToolTip="收起面板(Ctrl+G 唤回;右键菜单可退出)"/>
        </StackPanel>
      </Grid>
      <TextBlock x:Name="Meta" Text="正在读取…" FontSize="11" Foreground="#66FFFFFF" Margin="0,5,0,12"/>

      <!-- 额度行 1 -->
      <Grid>
        <TextBlock x:Name="R1Label" Text="🕐  5 小时 Prompt 池" FontSize="13.5" FontWeight="SemiBold" Foreground="#EEF0F4"/>
        <TextBlock x:Name="R1Value" Text="" FontSize="13" HorizontalAlignment="Right" Foreground="#E2E6EA"/>
      </Grid>
      <Border Height="7" CornerRadius="3.5" Background="#2A2D33" Margin="0,5" ClipToBounds="True">
        <Border x:Name="R1Fill" Height="7" CornerRadius="3.5" HorizontalAlignment="Left" Width="0" Background="#33B873"/>
      </Border>
      <TextBlock x:Name="R1Sub" Text="" FontSize="11" Foreground="#73FFFFFF"/>
      <Rectangle Height="0" Margin="0,5"/>

      <!-- 额度行 2 -->
      <Grid>
        <TextBlock x:Name="R2Label" Text="📅  每周额度" FontSize="13.5" FontWeight="SemiBold" Foreground="#EEF0F4"/>
        <TextBlock x:Name="R2Value" Text="" FontSize="13" HorizontalAlignment="Right" Foreground="#E2E6EA"/>
      </Grid>
      <Border Height="7" CornerRadius="3.5" Background="#2A2D33" Margin="0,5" ClipToBounds="True">
        <Border x:Name="R2Fill" Height="7" CornerRadius="3.5" HorizontalAlignment="Left" Width="0" Background="#33B873"/>
      </Border>
      <TextBlock x:Name="R2Sub" Text="" FontSize="11" Foreground="#73FFFFFF"/>
      <Rectangle Height="0" Margin="0,5"/>

      <!-- 额度行 3 -->
      <Grid>
        <TextBlock x:Name="R3Label" Text="🔧  MCP 工具调用 (1个月)" FontSize="13.5" FontWeight="SemiBold" Foreground="#EEF0F4"/>
        <TextBlock x:Name="R3Value" Text="" FontSize="13" HorizontalAlignment="Right" Foreground="#E2E6EA"/>
      </Grid>
      <Border Height="7" CornerRadius="3.5" Background="#2A2D33" Margin="0,5" ClipToBounds="True">
        <Border x:Name="R3Fill" Height="7" CornerRadius="3.5" HorizontalAlignment="Left" Width="0" Background="#33B873"/>
      </Border>
      <TextBlock x:Name="R3Sub" Text="" FontSize="11" Foreground="#73FFFFFF"/>

      <!-- 底部:24 小时用量 -->
      <Rectangle Height="1" Fill="#17FFFFFF" Margin="0,10,0,8"/>
      <Grid>
        <TextBlock Text="📊  近 24 小时" FontSize="12.5" FontWeight="Medium" Foreground="#EEF0F4"/>
        <TextBlock x:Name="FValue" Text="" FontSize="12.5" FontWeight="Medium" HorizontalAlignment="Right" Foreground="#F5F6F8"/>
      </Grid>
      <TextBlock x:Name="FSub" Text="" FontSize="11" Foreground="#73FFFFFF" Margin="0,4,0,0"/>
      <TextBlock Text="Ctrl+G 唤出 / 收起 · 拖拽面板可移动位置" FontSize="10.5" Foreground="#4DFFFFFF" Margin="0,7,0,0"/>
    </StackPanel>
  </Border>
</Window>
'@

$win = [Windows.Markup.XamlReader]::Parse($xamlText)
$el = { param($n) $win.FindName($n) }
$Meta = & $el 'Meta'
$BtnRefresh = & $el 'BtnRefresh'
$BtnClose = & $el 'BtnClose'
$rows = @()
for ($i = 1; $i -le 3; $i++) {
  $rows += [pscustomobject]@{
    Label = & $el "R${i}Label"; Value = & $el "R${i}Value"
    Fill  = & $el "R${i}Fill";  Sub   = & $el "R${i}Sub"
  }
}
$FValue = & $el 'FValue'
$FSub   = & $el 'FSub'

# 内容总宽(窗口 340 - 外边距 20 - 内边距 40),进度条按此计算填充宽
$trackWidth = 355.0

# 初始位置:默认主屏右上角;若有保存的位置且仍在屏幕范围内则恢复
$posFile = Join-Path $env:USERPROFILE '.zcode\scripts\glm-usage-widget.pos.json'
$wa = [System.Windows.SystemParameters]::WorkArea
$win.Left = $wa.Right - $win.Width - 26
$win.Top  = $wa.Top + 16
if (Test-Path $posFile) {
  try {
    $pos = Get-Content $posFile -Raw | ConvertFrom-Json
    if ($pos.Left -is [double] -and $pos.Top -is [double] -and
        $pos.Left -ge ($wa.Left - 20) -and ($pos.Left + $win.Width) -le ($wa.Right + 20) -and
        $pos.Top -ge ($wa.Top - 20) -and ($pos.Top + 240) -le ($wa.Bottom + 20)) {
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
# 与 macOS 版一致的三档配色:>=85 红,>=60 橙,其余绿
function RateColor([double]$p) {
  if ($p -ge 85) { '#FF5A5A' } elseif ($p -ge 60) { '#FFA94D' } else { '#33B873' }
}
# 行结构:左标签 / 右数值(中性浅色) / 胶囊进度条(按已用比例与档位色) / 灰色说明行
function Set-Row($row, $label, $value, $pct, $sub) {
  $p = [double]$pct
  $col = RateColor $p
  $row.Label.Text = $label
  $row.Value.Text = $value
  $row.Fill.Background = Brush $col
  $row.Fill.Width = [Math]::Round($trackWidth * [Math]::Min(100, [Math]::Max(0, $p)) / 100)
  $row.Sub.Text = $sub
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
  if (-not $parts) { $parts += '不到 1 分钟' }
  return ($parts -join ' ') + '后'
}
function Format-Tokens([double]$v) {
  if ($v -ge 1e8) { return '{0:F2} 亿' -f ($v / 1e8) }
  if ($v -ge 1e4) { return '{0:F1} 万' -f ($v / 1e4) }
  return '{0:N0}' -f $v
}

function Invoke-Refresh {
  $Meta.Text = '正在读取…'
  $raw = (& node $scriptPath --json 2>&1 | Out-String).Trim()
  $d = $null
  if ($raw) { try { $d = $raw | ConvertFrom-Json } catch { $d = $null } }
  if (-not $d -or -not $d.quota) {
    if ($raw -match '401') {
      $Meta.Text = '⚡ API Key 已失效或被更换 · 请在 ZCode 设置中更新,修复后自动恢复'
    } elseif ($raw) {
      $Meta.Text = '⚡ 获取失败:' + (($raw -split "`r?`n")[0])
    } else {
      $Meta.Text = '⚡ 获取失败(点 ↻ 重试)'
    }
    return
  }
  $q = $d.quota
  foreach ($l in $q.limits) {
    $p = [double]$l.percentage
    if ($l.type -eq 'TIME_LIMIT') {
      Set-Row $rows[2] '🔧  MCP 工具调用 (1个月)' ('{0:N0} / {1:N0} 次' -f $l.currentValue, $l.usage) $p `
        ('剩余 {0:N0} · ↻ {1} 重置 · {2}' -f $l.remaining, (Format-Clock $l.nextResetTime), (Format-Reset $l.nextResetTime))
    } elseif ($l.unit -eq 3) {
      Set-Row $rows[0] '🕐  5 小时 Prompt 池' ('剩余 {0:F1}%' -f (100 - $p)) $p `
        ('↻ {0} 重置 · {1}' -f (Format-Clock $l.nextResetTime), (Format-Reset $l.nextResetTime))
    } elseif ($l.unit -eq 6) {
      Set-Row $rows[1] '📅  每周额度' ('剩余 {0:F1}%' -f (100 - $p)) $p `
        ('↻ {0} 重置 · {1}' -f (Format-Clock $l.nextResetTime), (Format-Reset $l.nextResetTime))
    }
  }
  $t = $d.modelUsage.totalUsage
  $FValue.Text = ('{0:N0} 次 · {1} tokens' -f $t.totalModelCallCount, (Format-Tokens ([double]$t.totalTokensUsage)))
  $models = @($t.modelSummaryList | ForEach-Object { '{0} {1}' -f $_.modelName, (Format-Tokens ([double]$_.totalTokens)) })
  $FSub.Text = $models -join ' · '
  $Meta.Text = ('{0} 套餐 · 更新于 {1}' -f $q.level.ToUpper(), (Get-Date -Format 'HH:mm:ss'))
}

# 自动刷新间隔(分钟),按需调整
$refreshMinutes = 10
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMinutes($refreshMinutes)
$timer.Add_Tick({ Invoke-Refresh })

# 标题栏按钮:↻ 刷新,✕ 收起(隐藏不退出)
$BtnRefresh.Add_MouseEnter({ $BtnRefresh.Foreground = Brush '#F5F6F8' })
$BtnRefresh.Add_MouseLeave({ $BtnRefresh.Foreground = Brush '#99A0AA' })
$BtnRefresh.Add_MouseLeftButtonUp({ Invoke-Refresh })
$BtnClose.Add_MouseEnter({ $BtnClose.Foreground = Brush '#FF5A5A' })
$BtnClose.Add_MouseLeave({ $BtnClose.Foreground = Brush '#99A0AA' })
$BtnClose.Add_MouseLeftButtonUp({ $win.Hide() })

# 拖动(避开按钮),记忆位置
$win.Add_MouseLeftButtonDown({
  $src = $_.OriginalSource
  if ($src -ne $BtnRefresh -and $src -ne $BtnClose) { $win.DragMove(); Save-Pos }
})
$win.Add_Closing({ Save-Pos })

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

# ZCode 启动检测:从"没有任何 ZCode 进程"变为"有"才算一次真正的启动。
# 不能按"出现新 PID"判断——Electron 应用常驻多个同名子进程且动态回收重建,会频繁误唤起。
$script:zcodeWasRunning = [bool](Get-Process -Name 'ZCode' -ErrorAction SilentlyContinue)
$zcodeTimer = New-Object System.Windows.Threading.DispatcherTimer
$zcodeTimer.Interval = [TimeSpan]::FromMilliseconds(2000)
$zcodeTimer.Add_Tick({
  # 自存活检测:本脚本文件被删除(= 插件已卸载,缓存目录被移除)时,悬浮窗自行退出
  if ($PSCommandPath -and -not (Test-Path $PSCommandPath)) { [Environment]::Exit(0) }
  $running = [bool](Get-Process -Name 'ZCode' -ErrorAction SilentlyContinue)
  if ($running -and -not $script:zcodeWasRunning) {
    if (-not $win.IsVisible) { $win.Show() }
    $win.Activate()
  }
  $script:zcodeWasRunning = $running
})
$zcodeTimer.Start()

# 已有实例被再次"启动"时,通过命名事件把窗口调到前台(UI 线程轮询,勿用 ThreadPool 回调)
$showEvt = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, 'Global\GLM-Usage-Widget-Show')
$wakeTimer = New-Object System.Windows.Threading.DispatcherTimer
$wakeTimer.Interval = [TimeSpan]::FromMilliseconds(250)
$wakeTimer.Add_Tick({
  if ($showEvt.WaitOne(0)) {
    if (-not $win.IsVisible) { $win.Show() } else { $win.Activate() }
  }
})
$wakeTimer.Start()

# 右键菜单
$menuItems = @{}
foreach ($mi in $win.ContextMenu.Items) {
  if ($mi -is [System.Windows.Controls.MenuItem]) { $menuItems[$mi.Header] = $mi }
}
$menuItems['立即刷新'].Add_Click({ Invoke-Refresh })
$menuItems['退出'].Add_Click({
  try { if ($script:helper) { [GLMNative.Hotkey]::UnregisterHotKey($script:helper.Handle, 0xB001) | Out-Null } } catch { }
  $timer.Stop(); $win.Close(); [Environment]::Exit(0)
})

Invoke-Refresh
$timer.Start()
# 非模态显示 + 手动跑消息循环:Hide() 不会结束进程,可被热键/事件再次唤起
$win.Show()
[System.Windows.Threading.Dispatcher]::Run()
