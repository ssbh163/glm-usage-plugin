# GLM Coding Plan 桌面悬浮窗(Windows PowerShell 5.1+,零依赖)
# UI 逐项照抄 macOS GLMUsageHUD 规格:372 宽 / 18 内边距 / 16 圆角 / 6px 胶囊进度条 / macOS 标签色阶梯
# 配色与 ZCode 外观主题保持一致(探测 ZCode 窗口实际配色,深浅同步);GLM_WIDGET_THEME=light|dark 可强制
# 生命周期与插件绑定:由插件 SessionStart hook 拉起,插件卸载(本脚本被删)后自动退出
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

# 单实例保护 + 唤醒通道:必须放在 Add-Type/XAML 等耗时初始化之前,
# 否则主实例启动头几秒内到达的唤醒信号(事件尚未创建/轮询尚未开始)会被静默丢弃
$mutex = New-Object System.Threading.Mutex($false, 'Global\GLM-Usage-Widget')
$ownsMutex = $false
try { $ownsMutex = $mutex.WaitOne(0) } catch { $ownsMutex = $true }
if (-not $ownsMutex) {
  if ($args -notcontains 'NoShowIfExists') {
    # 手动再次启动:唤醒已有窗口(事件由主实例拿到互斥量后立即创建,无需重试)
    try { [System.Threading.EventWaitHandle]::OpenExisting('Global\GLM-Usage-Widget-Show').Set() | Out-Null } catch { }
  }
  exit
}
# 主实例:立即创建唤醒事件(initialState=false,不会误触发)
$showEvt = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, 'Global\GLM-Usage-Widget-Show')

# 唤醒文件:SessionStart hook(新会话)touch 一次,运行中的实例轮询到 mtime 变化即唤回
$wakeFile = Join-Path $env:USERPROFILE '.zcode\scripts\glm-usage-widget.wake'
$script:lastWake = if (Test-Path $wakeFile) { (Get-Item $wakeFile).LastWriteTimeUtc } else { [datetime]::MinValue }

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type -Namespace GLMNative -Name Hotkey -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
[DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
'@
# 磨砂玻璃背景(Windows BlurBehind + 浅黑色调)
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class GLMComposition {
  [StructLayout(LayoutKind.Sequential)]
  public struct AccentPolicy { public int AccentState; public int AccentFlags; public uint GradientColor; public int AnimationId; }
  [StructLayout(LayoutKind.Sequential)]
  public struct WCAD { public int Attrib; public IntPtr Data; public int SizeOfData; }
  [DllImport("user32.dll")]
  public static extern int SetWindowCompositionAttribute(IntPtr hwnd, ref WCAD data);
  public static bool EnableBlur(IntPtr hwnd, uint gradient) {
    var ap = new AccentPolicy { AccentState = 3, AccentFlags = 2, GradientColor = gradient };
    IntPtr p = Marshal.AllocHGlobal(Marshal.SizeOf(ap));
    Marshal.StructureToPtr(ap, p, false);
    var d = new WCAD { Attrib = 19, Data = p, SizeOfData = Marshal.SizeOf(ap) };
    int r = SetWindowCompositionAttribute(hwnd, ref d);
    Marshal.FreeHGlobal(p);
    return r != 0;
  }
}
'@

# ZCode 窗口像素探测:PrintWindow 截 ZCode 主窗口,采样最左侧栏亮度判断深浅
Add-Type -AssemblyName System.Drawing
Add-Type -Namespace GLMNative -Name ZCodeProbe -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdc, uint flags);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
'@

$scriptPath = Join-Path $env:USERPROFILE '.zcode\scripts\glm-usage.mjs'
if (-not (Test-Path $scriptPath)) {
  $cached = Get-ChildItem "$env:USERPROFILE\.zcode\cli\plugins\cache\*\glm-usage\*\skills\glm-usage\scripts\glm-usage.mjs" |
    Sort-Object FullName -Descending | Select-Object -First 1
  if ($cached) { $scriptPath = $cached.FullName }
}

# —— 以下 XAML 与 GLMUsageHUD.swift 的 HUDMetrics/HUDContentView 布局一一对应 ——
# 面板 372 宽(高自适应,官方公式约 306);pad 18;圆角 16;边框白 10%
# 字号阶梯:标题 14 bold / meta 10.5 / 行标题 12.5 semibold / 行数值 12 / sub 10.5 / footer 11.5 / hint 10
# 颜色(macOS 暗色标签阶梯):labelColor 白 / secondary 白65% / tertiary 白50% / quaternary 白30%
$xamlText = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="GLM Usage" Topmost="True" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" ShowInTaskbar="False" ResizeMode="NoResize" ShowActivated="False"
        Width="372" SizeToContent="Height">
  <Window.Resources>
    <!-- 配色走 DynamicResource,Apply-Theme 按系统浅色/深色整体切换(对齐 macOS 版材质策略) -->
    <SolidColorBrush x:Key="LabelBrush" Color="#FFFFFF"/>
    <SolidColorBrush x:Key="SecondaryBrush" Color="#A6FFFFFF"/>
    <SolidColorBrush x:Key="ValueBrush" Color="#8CFFFFFF"/>
    <SolidColorBrush x:Key="TertiaryBrush" Color="#80FFFFFF"/>
    <SolidColorBrush x:Key="QuaternaryBrush" Color="#24FFFFFF"/>
    <SolidColorBrush x:Key="TrackBrush" Color="#24FFFFFF"/>
    <SolidColorBrush x:Key="SeparatorBrush" Color="#2EFFFFFF"/>
    <SolidColorBrush x:Key="BorderBrushR" Color="#1AFFFFFF"/>
    <SolidColorBrush x:Key="RootBgBrush" Color="#E014171C"/>
  </Window.Resources>
  <Window.ContextMenu>
    <ContextMenu>
      <MenuItem x:Name="MenuRefresh" Header="立即刷新"/>
      <Separator/>
      <MenuItem x:Name="MenuExit" Header="退出"/>
    </ContextMenu>
  </Window.ContextMenu>
  <Border x:Name="Root" CornerRadius="16" Background="{DynamicResource RootBgBrush}" BorderBrush="{DynamicResource BorderBrushR}" BorderThickness="1"
          Margin="10" Padding="18">
    <StackPanel>
      <!-- 标题行:y=pad-2,h20;按钮 13pt medium secondaryLabel -->
      <Grid Height="20">
        <TextBlock Text="⚡ GLM Coding Plan" FontSize="14" FontWeight="Bold" Foreground="{DynamicResource LabelBrush}"
                   VerticalAlignment="Center"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
          <TextBlock x:Name="BtnRefresh" Text="↻" FontSize="13" Foreground="{DynamicResource SecondaryBrush}" Cursor="Hand"
                     ToolTip="立即刷新" Margin="0,0,12,0"/>
          <TextBlock x:Name="BtnClose" Text="✕" FontSize="13" FontWeight="Medium" Foreground="{DynamicResource SecondaryBrush}"
                     Cursor="Hand" ToolTip="收起面板(Ctrl+G 唤回;右键菜单可退出)"/>
        </StackPanel>
      </Grid>
      <!-- meta:14 高,+12 -->
      <TextBlock x:Name="Meta" Text="正在读取…" FontSize="10.5" Foreground="{DynamicResource TertiaryBrush}" Margin="0,1,0,12"/>

      <!-- 额度行 = QuotaRowView(46):标题16 → +4 → 条6 → +4 → sub14,行间 8 -->
      <StackPanel x:Name="Row1">
        <Grid Height="16">
          <TextBlock x:Name="R1Label" Text="" FontSize="12.5" FontWeight="SemiBold" Foreground="{DynamicResource LabelBrush}"/>
          <TextBlock x:Name="R1Value" Text="" FontSize="12" FontWeight="Bold" HorizontalAlignment="Right" Foreground="{DynamicResource ValueBrush}"/>
        </Grid>
        <Border Height="6" CornerRadius="3" Background="{DynamicResource TrackBrush}" Margin="0,4,0,4" ClipToBounds="True">
          <Border x:Name="R1Fill" Height="6" CornerRadius="3" HorizontalAlignment="Left" Width="0" Background="#33B873"/>
        </Border>
        <TextBlock x:Name="R1Sub" Text="" FontSize="10.5" Foreground="{DynamicResource QuaternaryBrush}"/>
      </StackPanel>
      <StackPanel x:Name="Row2" Margin="0,8,0,0">
        <Grid Height="16">
          <TextBlock x:Name="R2Label" Text="" FontSize="12.5" FontWeight="SemiBold" Foreground="{DynamicResource LabelBrush}"/>
          <TextBlock x:Name="R2Value" Text="" FontSize="12" FontWeight="Bold" HorizontalAlignment="Right" Foreground="{DynamicResource ValueBrush}"/>
        </Grid>
        <Border Height="6" CornerRadius="3" Background="{DynamicResource TrackBrush}" Margin="0,4,0,4" ClipToBounds="True">
          <Border x:Name="R2Fill" Height="6" CornerRadius="3" HorizontalAlignment="Left" Width="0" Background="#33B873"/>
        </Border>
        <TextBlock x:Name="R2Sub" Text="" FontSize="10.5" Foreground="{DynamicResource QuaternaryBrush}"/>
      </StackPanel>
      <StackPanel x:Name="Row3" Margin="0,8,0,0">
        <Grid Height="16">
          <TextBlock x:Name="R3Label" Text="" FontSize="12.5" FontWeight="SemiBold" Foreground="{DynamicResource LabelBrush}"/>
          <TextBlock x:Name="R3Value" Text="" FontSize="12" FontWeight="Bold" HorizontalAlignment="Right" Foreground="{DynamicResource ValueBrush}"/>
        </Grid>
        <Border Height="6" CornerRadius="3" Background="{DynamicResource TrackBrush}" Margin="0,4,0,4" ClipToBounds="True">
          <Border x:Name="R3Fill" Height="6" CornerRadius="3" HorizontalAlignment="Left" Width="0" Background="#33B873"/>
        </Border>
        <TextBlock x:Name="R3Sub" Text="" FontSize="10.5" Foreground="{DynamicResource QuaternaryBrush}"/>
      </StackPanel>

      <!-- +2 分隔线 +11 -->
      <Rectangle Height="1" Fill="{DynamicResource SeparatorBrush}" Margin="0,10,0,10"/>
      <!-- footer:11.5 medium labelColor,一行式;sub 10.5 tertiary -->
      <TextBlock x:Name="FLabel" Text="" FontSize="11.5" FontWeight="Medium" Foreground="{DynamicResource LabelBrush}"/>
      <TextBlock x:Name="FSub" Text="" FontSize="10.5" Foreground="{DynamicResource TertiaryBrush}" Margin="0,3,0,0"/>
      <TextBlock x:Name="Hint" Text="Ctrl+G 唤出 / 收起 · 拖拽面板可移动位置" FontSize="10" Foreground="{DynamicResource QuaternaryBrush}" Margin="0,2,0,0"/>
    </StackPanel>
  </Border>
</Window>
'@

$win = [Windows.Markup.XamlReader]::Parse($xamlText)
$el = { param($n) $win.FindName($n) }
$Meta = & $el 'Meta'
$BtnRefresh = & $el 'BtnRefresh'
$BtnClose = & $el 'BtnClose'
$FLabel = & $el 'FLabel'
$FSub = & $el 'FSub'
$Hint = & $el 'Hint'
$rows = @()
for ($i = 1; $i -le 3; $i++) {
  $rows += [pscustomobject]@{
    Panel = & $el "Row${i}"
    Label = & $el "R${i}Label"; Value = & $el "R${i}Value"
    Fill  = & $el "R${i}Fill";  Sub   = & $el "R${i}Sub"
  }
}

# 内容宽 372 - 36 = 336;条填充最小宽度 = 条高(极小比例也显示圆点,同 BarView)
$trackWidth = 336.0

# 初始位置:主屏右上角;有保存位置且在屏幕范围内则恢复
$posFile = Join-Path $env:USERPROFILE '.zcode\scripts\glm-usage-widget.pos.json'
$wa = [System.Windows.SystemParameters]::WorkArea
$win.Left = $wa.Right - $win.Width - 26
$win.Top  = $wa.Top + 16
if (Test-Path $posFile) {
  try {
    $pos = Get-Content $posFile -Raw | ConvertFrom-Json
    if ($pos.Left -is [double] -and $pos.Top -is [double] -and
        $pos.Left -ge ($wa.Left - 20) -and ($pos.Left + $win.Width) -le ($wa.Right + 20) -and
        $pos.Top -ge ($wa.Top - 20) -and ($pos.Top + 260) -le ($wa.Bottom + 20)) {
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

# —— 主题:与 ZCode 外观保持一致(像素探测 ZCode 主窗口侧边栏),不读写任何 Windows 主题设置 ——
# 探测失败(窗口最小化/截取失败)沿用最近一次结果;从未成功过才回退 Windows 应用模式(只读)
# 浅色 = macOS 浅色标签阶梯(#3C3C43 系);GLM_WIDGET_THEME=light|dark 强制指定(调试用)
$themeOverride = $env:GLM_WIDGET_THEME
$themes = @{
  dark = @{ Label='#FFFFFF'; Secondary='#A6FFFFFF'; Value='#8CFFFFFF'; Tertiary='#80FFFFFF'
            Quaternary='#24FFFFFF'; Track='#24FFFFFF'; Separator='#2EFFFFFF'; Border='#1AFFFFFF'
            RootSemi='#E014171C'; RootOpaque='#F01C1F24'; BlurTint=0x991A1A18 }
  light = @{ Label='#FF1D1D1F'; Secondary='#A63C3C43'; Value='#A63C3C43'; Tertiary='#803C3C43'
             Quaternary='#993C3C43'; Track='#293C3C43'; Separator='#2E3C3C43'; Border='#1A000000'
             RootSemi='#E0F2F2F4'; RootOpaque='#F0F2F2F5'; BlurTint=0x99E9EAEC }
}
$script:lastKnownDark = $null
function Get-IsDarkTheme {
  if ($themeOverride -eq 'dark') { return $true }
  if ($themeOverride -eq 'light') { return $false }
  try {
    $z = Get-Process -Name 'ZCode' -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
    if ($z) {
      $r = New-Object GLMNative.ZCodeProbe+RECT
      [GLMNative.ZCodeProbe]::GetWindowRect($z.MainWindowHandle, [ref]$r) | Out-Null
      $w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
      if ($w -gt 100 -and $h -gt 100) {
        $bmp = New-Object System.Drawing.Bitmap($w, $h)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $hdc = $g.GetHdc()
        $ok = [GLMNative.ZCodeProbe]::PrintWindow($z.MainWindowHandle, $hdc, 2)
        $g.ReleaseHdc($hdc); $g.Dispose()
        if ($ok) {
          $lum = 0.0; $n = 0
          foreach ($fx in @(0.012, 0.018, 0.024)) {
            foreach ($fy in @(0.3, 0.5, 0.7)) {
              $c = $bmp.GetPixel([int]($w * $fx), [int]($h * $fy))
              $lum += 0.299 * $c.R + 0.587 * $c.G + 0.114 * $c.B; $n++
            }
          }
          $bmp.Dispose()
          $script:lastKnownDark = (($lum / $n) -lt 110)
          return $script:lastKnownDark
        }
        $bmp.Dispose()
      }
    }
  } catch { }
  if ($null -ne $script:lastKnownDark) { return $script:lastKnownDark }
  try {
    $v = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Themes\Personalize').GetValue('AppsUseLightTheme')
    return ($v -eq 0)
  } catch { return $true }
}
$script:blurOk = $true
function Apply-Theme {
  $script:theme = if (Get-IsDarkTheme) { $themes.dark } else { $themes.light }
  $map = @{ Label='LabelBrush'; Secondary='SecondaryBrush'; Value='ValueBrush'
            Tertiary='TertiaryBrush'; Quaternary='QuaternaryBrush'; Track='TrackBrush'
            Separator='SeparatorBrush'; Border='BorderBrushR' }
  foreach ($k in $map.Keys) {
    $b = $win.Resources[$map[$k]]
    # 注意:改 .Color 必须用 ColorConverter(返回 Color);BrushConverter 返回 Brush 会抛异常
    if ($b) { $b.Color = [System.Windows.Media.ColorConverter]::ConvertFromString($script:theme[$k]) }
  }
  $rootBrush = $win.Resources['RootBgBrush']
  if ($rootBrush) {
    # 磨砂可用时半透明底让窗口后的模糊透出来;失败则退不透明底
    $bg = if ($script:blurOk) { $script:theme.RootSemi } else { $script:theme.RootOpaque }
    $rootBrush.Color = [System.Windows.Media.ColorConverter]::ConvertFromString($bg)
  }
  if ($script:helper -and $script:blurOk) {
    [GLMComposition]::EnableBlur($script:helper.Handle, $script:theme.BlurTint) | Out-Null
  }
}
# Fmt.tint:>=85 红,>=60 橙,其余绿(0.20,0.72,0.45)
function RateColor([double]$p) {
  if ($p -ge 85) { '#FF5A5A' } elseif ($p -ge 60) { '#FFA94D' } else { '#33B873' }
}
function Set-Row($row, $label, $value, $pct, $sub) {
  $p = [double]$pct
  $col = RateColor $p
  $row.Label.Text = $label
  $row.Value.Text = $value
  $row.Fill.Background = Brush $col
  # BarView:填充宽 = max(比例*宽, 条高) —— 极小也画出圆点
  $w = [Math]::Round($trackWidth * [Math]::Min(100, [Math]::Max(0, $p)) / 100)
  $row.Fill.Width = [Math]::Max($w, 6)
  $row.Sub.Text = $sub
}
function Format-Clock($ms) {
  if (-not $ms -or $ms -le 0) { return '' }
  [DateTimeOffset]::FromUnixTimeMilliseconds($ms).LocalDateTime.ToString('MM/dd HH:mm')
}
# Fmt.countdown:"5 天 3 小时 13 分钟后";<=0 即将重置
function Format-Reset($ms) {
  if (-not $ms -or $ms -le 0) { return '即将重置' }
  $span = [DateTimeOffset]::FromUnixTimeMilliseconds($ms) - [DateTimeOffset]::Now
  if ($span.TotalSeconds -le 0) { return '即将重置' }
  $parts = @()
  if ($span.Days) { $parts += ("{0} 天" -f $span.Days) }
  if ($span.Hours) { $parts += ("{0} 小时" -f $span.Hours) }
  if ($span.Minutes -or ($span.Days -eq 0 -and $span.Hours -eq 0)) { $parts += ("{0} 分钟" -f $span.Minutes) }
  if (-not $parts) { $parts += '不到 1 分钟' }
  return ($parts -join ' ') + '后'
}
# Fmt.tokens:1.25 亿 / 9.2 万
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
    # renderError:⚠️ 查询失败 + 消息放 sub,footer 提示重试
    $Meta.Text = '读取失败'
    $msg = if ($raw -match '401') { 'API Key 已失效或被更换,请在 ZCode 设置中更新' }
      elseif ($raw) { ($raw -split "`r?`n")[0] } else { '网络错误,点右上角 ↻ 重试' }
    Set-Row $rows[0] '⚠️  查询失败' '' 0 $msg
    foreach ($r in $rows | Select-Object -Skip 1) { $r.Panel.Visibility = 'Collapsed' }
    $FLabel.Text = '可点右上角 ↻ 重试'
    $FSub.Text = ''
    return
  }
  foreach ($r in $rows) { $r.Panel.Visibility = 'Visible' }
  $q = $d.quota
  foreach ($l in $q.limits) {
    $p = [double]$l.percentage
    if ($l.type -eq 'TIME_LIMIT') {
      Set-Row $rows[2] '🔧  MCP 工具调用（1个月）' ('{0:N0} / {1:N0} 次' -f $l.currentValue, $l.usage) $p `
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
  $FLabel.Text = ('📊  当日　{0:N0} 次 · {1} tokens' -f $t.totalModelCallCount, (Format-Tokens ([double]$t.totalTokensUsage)))
  $models = @($t.modelSummaryList | ForEach-Object { '{0} {1}' -f $_.modelName, (Format-Tokens ([double]$_.totalTokens)) })
  $FSub.Text = $models -join ' · '
  $Meta.Text = ('{0} 套餐 · 更新于 {1}' -f $q.level.ToUpper(), (Get-Date -Format 'HH:mm:ss'))
}

# 自动刷新间隔(分钟),按需调整
$refreshMinutes = 10
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMinutes($refreshMinutes)
$timer.Add_Tick({ Invoke-Refresh })

# ↻ 刷新,✕ 收起(隐藏不退出);悬停变亮
$BtnRefresh.Add_MouseEnter({ $BtnRefresh.Foreground = Brush $script:theme.Label })
$BtnRefresh.Add_MouseLeave({ $BtnRefresh.Foreground = Brush $script:theme.Secondary })
$BtnRefresh.Add_MouseLeftButtonUp({ Invoke-Refresh })
$BtnClose.Add_MouseEnter({ $BtnClose.Foreground = Brush '#FF5A5A' })
$BtnClose.Add_MouseLeave({ $BtnClose.Foreground = Brush $script:theme.Secondary })
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
  $hkOk = [GLMNative.Hotkey]::RegisterHotKey($script:helper.Handle, 0xB001, $script:hotkeyModifiers, $script:hotkeyKey)
  if (-not $hkOk) {
    # 全局热键被其他软件占用:醒目提示,避免"按了没反应"无从排查
    $mods = (@{ 1 = 'Alt'; 2 = 'Ctrl'; 4 = 'Shift'; 8 = 'Win' }[[int]$script:hotkeyModifiers])
    $key = [char]$script:hotkeyKey
    $Hint.Text = "⚠ ${mods}+$key 已被其他软件占用,快捷键不可用(改键:脚本顶部 `\$hotkeyKey)"
    $Hint.Foreground = Brush '#FFA94D'
  }
  # 磨砂玻璃:BlurBehind + 随主题的深/浅 tint;失败回退不透明底色
  $Root = $win.FindName('Root')
  $script:blurOk = [GLMComposition]::EnableBlur($script:helper.Handle, $script:theme.BlurTint)
  if (-not $script:blurOk) {
    $Root.Background = Brush $script:theme.RootOpaque
  }
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

# ZCode 启动检测:none→running 才算启动(避免 Electron 子进程重建误唤起)
$script:zcodeWasRunning = [bool](Get-Process -Name 'ZCode' -ErrorAction SilentlyContinue)
$zcodeTimer = New-Object System.Windows.Threading.DispatcherTimer
$zcodeTimer.Interval = [TimeSpan]::FromMilliseconds(2000)
$zcodeTimer.Add_Tick({
  # ZCode 外观跟随:探测 ZCode 主窗口配色,变化即整体换肤(并记日志便于排查)
  $dark = Get-IsDarkTheme
  if ($dark -ne $script:isDark) {
    $script:isDark = $dark
    Apply-Theme
    try {
      Add-Content -Path (Join-Path $env:USERPROFILE '.zcode\scripts\widget-theme.log') `
        -Value ("{0} -> {1}" -f (Get-Date -Format 'MM/dd HH:mm:ss'), $(if ($dark) { 'dark' } else { 'light' }))
    } catch { }
  }
  # 自存活检测:本脚本被删(= 插件已卸载)则自行退出
  if ($PSCommandPath -and -not (Test-Path $PSCommandPath)) { [Environment]::Exit(0) }
  $running = [bool](Get-Process -Name 'ZCode' -ErrorAction SilentlyContinue)
  if ($running -and -not $script:zcodeWasRunning) {
    # ZCode 启动:唤起
    if (-not $win.IsVisible) { $win.Show() }
    $win.Activate()
  }
  elseif (-not $running -and $script:zcodeWasRunning) {
    # ZCode 完全退出:悬浮窗随之退出(生命周期完全绑定)
    try { if ($script:helper) { [GLMNative.Hotkey]::UnregisterHotKey($script:helper.Handle, 0xB001) | Out-Null } } catch { }
    $timer.Stop()
    $win.Close()
    [Environment]::Exit(0)
  }
  $script:zcodeWasRunning = $running
})
$zcodeTimer.Start()

# 唤醒轮询:双通道 —— 命名事件(手动再次启动)+ 唤醒文件(SessionStart hook touch)
$wakeTimer = New-Object System.Windows.Threading.DispatcherTimer
$wakeTimer.Interval = [TimeSpan]::FromMilliseconds(250)
$wakeTimer.Add_Tick({
  $wake = $showEvt.WaitOne(0)
  $wi = Get-Item $wakeFile -ErrorAction SilentlyContinue
  if ($wi -and $wi.LastWriteTimeUtc -gt $script:lastWake) {
    $script:lastWake = $wi.LastWriteTimeUtc
    $wake = $true
  }
  # 只负责唤回;已可见时不 Activate,避免抢焦点(Topmost 本就在最上层)
  if ($wake -and -not $win.IsVisible) { $win.Show() }
})
$wakeTimer.Start()

$menuItems = @{}
foreach ($mi in $win.ContextMenu.Items) {
  if ($mi -is [System.Windows.Controls.MenuItem]) { $menuItems[$mi.Header] = $mi }
}
$menuItems['立即刷新'].Add_Click({ Invoke-Refresh })
$menuItems['退出'].Add_Click({
  try { if ($script:helper) { [GLMNative.Hotkey]::UnregisterHotKey($script:helper.Handle, 0xB001) | Out-Null } } catch { }
  $timer.Stop(); $win.Close(); [Environment]::Exit(0)
})

# 应用主题(与 ZCode 外观一致);此后 zcodeTimer 每 2 秒探测 ZCode 配色并跟随切换
$script:isDark = Get-IsDarkTheme
try { Apply-Theme } catch {
  try { Add-Content (Join-Path $env:USERPROFILE '.zcode\scripts\widget-theme.log') ("startup Apply-Theme THREW: " + $_.Exception.Message) } catch { }
}

Invoke-Refresh
$timer.Start()
$win.Show()
[System.Windows.Threading.Dispatcher]::Run()
