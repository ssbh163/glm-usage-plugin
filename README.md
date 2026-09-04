# glm-usage — 0.0.1

在 ZCode 中用智谱(Coding Plan)**API Key 登录**时,端内看不到 5 小时池和每周额度。这个插件通过智谱官方监控接口(与官方 glm-plan-usage 插件同源)把额度带回来:

| 显示项 | 内容 |
|---|---|
| ⏱ 5 小时 Prompt 池 | 已用百分比、重置倒计时 |
| 📅 每周额度 | 已用百分比、重置时间 |
| 🔧 MCP 工具调用(每月) | 已用/总量、各工具明细 |
| 📊 近 24 小时用量 | 调用次数、token 消耗、按模型汇总 |

## 效果预览

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 ⚡ GLM Coding Plan 用量
    PRO 套餐 · open.bigmodel.cn · 2026/9/3 20:20
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

 🕐  5 小时 Prompt 池      ▰▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱  6.0%
      剩余 94.0%
      ↻ 09/04 00:36 重置(4 小时 16 分钟后)

 📅  每周额度              ▰▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱  4.0%
      剩余 96.0%
      ↻ 09/09 18:04 重置(5 天 21 小时后)

 🔧  MCP 工具调用(1个月)   ▰▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱  3.0%
      已用 30 / 1,000 次 · 剩余 970
      ↻ 09/22 18:04 重置(18 天 21 小时后)
      search-prime 25 · web-reader 2 · zread 3

 📊  近 24 小时模型用量    222 次 · 1274.5 万 tokens
```

在支持颜色的终端中,进度条按用量自动变色:<50% 绿色、50–80% 黄色、≥80% 红色。

## 前提条件

- [ZCode](https://zcode.z.ai) 桌面版
- 已在 ZCode 中配置智谱 Coding Plan 的 **API Key**(设置 → 模型,插件自动读取,无需手动填)
- Node.js ≥ 18(终端输入 `node -v` 检查)

## 安装

### 方式 A · 从 GitHub 安装(推荐)

1. ZCode 左侧栏 → **插件市场** → **发现** 页
2. 点右上角 **+** 添加插件市场,选择 **GitHub 仓库**,填入本仓库地址
3. 在市场列表中找到 **glm-usage**,点 **获取/安装**

> 国内网络克隆失败时,先设置环境变量 `ZCODE_HTTP_PROXY=http://host:port` 再重试(ZCode 只认这个变量,不吃普通的 http_proxy)。

### 方式 B · 本地安装

1. 下载本仓库(绿色按钮 Code → Download ZIP)并解压
2. ZCode → 插件市场 → 发现 → **+** → **本地目录**,选中解压后的**仓库根目录**(即包含 `marketplace.json` 的那一层)
3. 安装 **glm-usage**

### 方式 C · 只用脚本,不装插件

下载 [glm-usage.mjs](plugins/glm-usage/skills/glm-usage/scripts/glm-usage.mjs)(悬浮窗需连同 [glm-usage-widget.ps1](plugins/glm-usage/skills/glm-usage/scripts/glm-usage-widget.ps1) 一起下载,建议直接下载整个 zip),运行:

```bash
node glm-usage.mjs --install
```

一条命令装完全部:查询脚本、`/usage` 命令、桌面悬浮窗(**装完立即弹出**)、登录自启。卸载同样一条命令:`node glm-usage.mjs --uninstall`。

## 使用

### 1. ZCode 对话内

安装插件后**新开一个对话**(命令在会话启动时加载):

- 输入 `/glm-usage:usage`
- 或直接问:"查一下 Coding Plan 用量""5 小时池还剩多少""周额度什么时候重置"

助手会运行脚本并把结果整理成表格。

### 2. 终端直接运行

```bash
node ~/.zcode/scripts/glm-usage.mjs            # 卡片式输出
node ~/.zcode/scripts/glm-usage.mjs --json     # 原始 JSON
```

插件安装者也可以直接用插件缓存里的脚本(免 --install):

```bash
node "$(ls -d "$HOME/.zcode/cli/plugins/cache"/*/glm-usage/*/skills/glm-usage/scripts/glm-usage.mjs | sort -V | tail -1)"
```

### 3. 桌面悬浮窗(按设备自动选择 UI,随插件启停)

插件自带 **两套悬浮窗 UI**,SessionStart hook 会按当前设备自动选择,无需任何手动配置;**卸载插件后悬浮窗自动退出**,不残留开机自启或后台进程。

| 设备 | UI | 说明 |
|---|---|---|
| **Windows** | WPF 磨砂玻璃卡片(浅黑玻璃,社区原版风格) | Ctrl+G 显示/隐藏;启动 ZCode 自动唤起;ZCode 完全退出时随之退出;✕ 隐藏、右键退出 |
| **macOS** | 原生 HUD 面板(社区移植的 GLMUsageHUD) | 编译一次即可:进入插件目录 `macos/` 执行 `bash build.sh`,生成 `GLMUsageHUD.app`;之后每次会话自动在后台打开 |
| 其他系统 | (无悬浮窗,仅命令/技能/注入) | — |

两套 UI 数据口径一致(同一个查询脚本),视觉各自贴合系统原生质感。

- Windows 版:右上角 **✕** 只是隐藏(进程驻留),**右键菜单 → 退出**彻底关闭;重复启动自动去重;位置记忆
- macOS 版:菜单栏有 ⚡ 兜底图标;详见 `macos/README.md`
- API Key 失效时面板明确提示,修复后自动恢复

> 不装插件只想要 Windows 悬浮窗?用下方"方式 C"的 `--install` 独立安装(带 Windows 登录自启),用 `--uninstall` 一键完整卸载。

### 4. 新会话自动注入

插件自带的 SessionStart hook 会在每个新对话开头注入一行额度摘要,无需任何配置。卸载插件即停止注入。

## 隐私与安全

- 插件**不含任何密钥**。脚本运行时从本机 ZCode 配置(`~/.zcode/v2/config.json`)读取你自己的 API Key
- 请求只发往智谱官方域名(`open.bigmodel.cn` / `api.z.ai`),不经过任何第三方服务器
- 查询走官方监控接口,不消耗 prompt 额度

## 常见问题

**Q:提示"未找到 Coding Plan API Key"?**
先在 ZCode 设置里配好智谱 Coding Plan 的 API Key;或设置环境变量 `ANTHROPIC_AUTH_TOKEN` + `ANTHROPIC_BASE_URL`,或运行时传 `--key <apiKey> --base <baseURL>`。

**Q:HTTP 401?**
API Key 无效或过期,去智谱开放平台重新获取。

**Q:不用 ZCode,能在 Claude Code 里用吗?**
可以。设置 `ANTHROPIC_AUTH_TOKEN=https://open.bigmodel.cn/api/anthropic` 对应的环境变量后直接跑脚本(国际站用 `https://api.z.ai/api/anthropic`)。

**Q:Windows 悬浮窗按 Ctrl+G 没反应?**
两种情况:①悬浮窗进程没在运行(它只随 ZCode 存活,ZCode 完全退出后自退;重开 ZCode 或新开一个对话即恢复);②全局热键被其他软件占用(截图/翻译工具等)——此时悬浮窗底部会显示橙色 ⚠ 提示,可关闭占用软件或在脚本顶部修改 `$hotkeyModifiers`/`$hotkeyKey` 换键。

**Q:额度数字和网页后台对不上?**
查询接口是智谱未公开文档的监控接口,官方若调整字段,更新脚本中的映射即可(`TOKENS_LIMIT` unit=3 是 5 小时池、unit=6 是每周,`TIME_LIMIT` 是 MCP 每月)。

## 目录结构

```
glm-usage-plugin/                       ← 市场仓库根目录
├── .zcode-plugin/marketplace.json      ← 市场清单
├── marketplace.json                    ← 根目录副本(兼容不同读取位置)
└── plugins/glm-usage/                  ← 插件本体
    ├── .zcode-plugin/plugin.json
    ├── hooks/hooks.json                ← SessionStart:按设备拉起悬浮窗 + 注入用量摘要
    ├── commands/usage.md               ← /glm-usage:usage 命令
    ├── macos/                          ← macOS 原生悬浮窗(GLMUsageHUD.swift + build.sh)
    └── skills/glm-usage/
        ├── SKILL.md
        └── scripts/
            ├── glm-usage.mjs           ← 查询脚本(零依赖,支持 --install/--uninstall)
            ├── glm-usage-widget.ps1    ← Windows 悬浮窗(磨砂玻璃卡片)
            ├── widget-launch.mjs       ← 跨平台启动器(按设备分发)
            └── widget-launch.vbs       ← Windows 启动器(vbs,免黑窗)
```

## 卸载

**插件方式**(推荐,卸载即全清):

1. ZCode 设置 → 插件管理 → 已安装 → glm-usage → 卸载
2. 完成。悬浮窗会在数秒内检测到插件缓存被移除而自动退出,会话注入同时停止,不残留开机自启、进程或配置

**独立脚本方式**(曾运行过 `--install` 的用户):

```bash
node glm-usage.mjs --uninstall
```

一键清除全部:悬浮窗进程、开机自启、`~/.zcode/scripts/` 下的脚本、`/usage` 命令、cli 配置中的 hook。

## License

MIT
